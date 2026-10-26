import AVFoundation
import Observation
import SwiftUI
import UIKit

/// Compression before encryption (Android MediaUtils): photos to JPEG at most 2048 px, videos
/// re-encoded at medium quality; a tiny JPEG thumbnail travels (encrypted) in the message itself.
enum MediaPrep {
    struct Prepared {
        let data: Data
        let thumbnail: Data?
    }

    static func image(_ data: Data) -> Prepared? {
        guard let source = UIImage(data: data) else { return nil }
        let full = resized(source, maxSide: 2048)
        guard let jpeg = full.jpegData(compressionQuality: 0.82) else { return nil }
        return Prepared(data: jpeg, thumbnail: thumbnail(of: source))
    }

    static func video(at url: URL) async -> Prepared? {
        let asset = AVURLAsset(url: url)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer {
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.removeItem(at: url)
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { return nil }
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await export.export()
        guard export.status == .completed, let data = try? Data(contentsOf: out) else {
            AppLog.write("Video export failed: \(export.error?.localizedDescription ?? "unknown")")
            return nil
        }
        let still = await frame(of: asset)
        return Prepared(data: data, thumbnail: still.flatMap { thumbnail(of: $0) })
    }

    static func videoThumbnail(_ url: URL) async -> UIImage? {
        await frame(of: AVURLAsset(url: url))
    }

    private static func frame(of asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        guard let cg = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: cg)
    }

    /// ~1 KB preview, like Android's MediaThumbnails.
    private static func thumbnail(of image: UIImage) -> Data? {
        resized(image, maxSide: 48).jpegData(compressionQuality: 0.5)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Voice notes: AAC in .m4a - the same format Android records, so both play each other's.
@MainActor
@Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fileURL: URL?

    func start() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            AppLog.write("Microphone permission denied")
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else { return false }
            self.recorder = recorder
            fileURL = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed = self.recorder?.currentTime ?? 0
                }
            }
            return true
        } catch {
            AppLog.write("Recording failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Returns the recording, or nil when cancelled / shorter than half a second.
    func stop(send: Bool) -> Data? {
        timer?.invalidate()
        timer = nil
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileURL else { return nil }
        fileURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard send, duration >= 0.5 else { return nil }
        return try? Data(contentsOf: url)
    }
}

/// Expanding red ring behind the mic while recording.
struct PulseRing: View {
    @State private var on = false

    var body: some View {
        Circle().fill(Color.red.opacity(0.3))
            .scaleEffect(on ? 1.7 : 1)
            .opacity(on ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

/// Hold to record, release to send, drag left to cancel, drag up to lock (Telegram): once
/// locked the finger can go, and the recording ends with Send or Cancel.
struct VoiceButton: View {
    let recorder: VoiceRecorder
    let onSend: (Data) -> Void
    @State private var pressed = false
    @State private var cancelled = false
    @State private var locked = false
    @State private var lift: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            if recorder.isRecording {
                Text(String(format: "%d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .monospacedDigit().foregroundStyle(cancelled ? Color.secondary : Color.red)
                if locked {
                    Button(tr("Отмена")) { finish(send: false) }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Safir.danger)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Text(cancelled ? "Отпустите для отмены" : "← отмена").font(.caption).foregroundStyle(.secondary)
                }
            }
            if locked && recorder.isRecording {
                Button { finish(send: true) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Safir.brandGradient))
                }
                .buttonStyle(PressableStyle())
                .transition(.scale.combined(with: .opacity))
            } else {
                mic
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: locked)
    }

    private var mic: some View {
        Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(recorder.isRecording ? Color.white : Safir.muted)
            .frame(width: 36, height: 36)
            .background {
                if recorder.isRecording {
                    ZStack {
                        PulseRing()
                        Circle().fill(Color.red)
                    }
                    .scaleEffect(1.25)
                } else {
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .scaleEffect(1.17)
                }
            }
            // The lock above the mic: rises with the finger, closes at the top.
            .overlay(alignment: .top) {
                if recorder.isRecording && pressed {
                    Image(systemName: lift > 60 ? "lock.fill" : "lock.open")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Safir.accent)
                        .frame(width: 34, height: 48)
                        .safirGlass(in: Capsule(), rim: true)
                        .offset(y: -64 - min(lift, 70) * 0.4)
                        .contentTransition(.symbolEffect(.replace))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recorder.isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressed {
                            pressed = true
                            cancelled = false
                            Task {
                                let started = await recorder.start()
                                // Released while the permission prompt / setup was running.
                                if started && !pressed && !locked { _ = recorder.stop(send: false) }
                            }
                        }
                        lift = max(0, -value.translation.height)
                        cancelled = value.translation.width < -80
                        if lift > 70 && !locked && recorder.isRecording {
                            Safir.tap(.medium)
                            locked = true
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        lift = 0
                        guard !locked else { return }
                        if recorder.isRecording, let data = recorder.stop(send: !cancelled) { onSend(data) }
                        cancelled = false
                    }
            )
    }

    private func finish(send: Bool) {
        Safir.tap(send ? .medium : .light)
        if recorder.isRecording, let data = recorder.stop(send: send) { onSend(data) }
        // The mic (and its gesture) left the screen when the lock closed, so onEnded never came.
        pressed = false
        locked = false
        cancelled = false
        lift = 0
    }
}
