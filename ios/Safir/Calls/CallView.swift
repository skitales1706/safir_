import SwiftUI
import WebRTC

/// In-app call screen: incoming (accept / decline), outgoing ringing and the active call, on a
/// moving Safir-colour backdrop. CallKit still shows the system screen on the lock screen.
struct CallView: View {
    private var call: CallService { CallService.shared }
    @State private var shown = DemoData.active

    private var remoteVideo: RTCVideoTrack? { call.participants.first(where: { $0.video != nil })?.video }
    private var ringing: Bool { call.phase == .ringingIn || call.phase == .ringingOut }
    // Endless animations keep UI tests from ever seeing the app idle, so screenshots are still.
    private var animated: Bool { !AppSettings.shared.reduceAnimations && !DemoData.active }
    private var avatarPath: String? {
        call.isGroup ? nil : call.participants.first.flatMap { ChatStore.shared.user($0.id)?.avatarUrl }
    }

    var body: some View {
        ZStack {
            // Video calls float on in Picture in Picture when the app goes to the background.
            CallPiPAnchor(track: remoteVideo).ignoresSafeArea()
            CallBackdrop(animated: animated)
            if let remote = remoteVideo {
                VideoTrackView(track: remote).ignoresSafeArea().transition(.opacity)
                LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                topBadge.padding(.top, 12)
                if remoteVideo == nil {
                    Spacer().frame(height: 28)
                    CallAvatar(name: call.title, path: avatarPath, ringing: ringing, animated: animated)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .padding(.bottom, 10)
                } else {
                    Spacer().frame(height: 16)
                }
                Text(verbatim: call.title)
                    .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).padding(.horizontal, 24)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let text = status(at: context.date)
                    Text(verbatim: text)
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: text)
                }
                .padding(.top, 6)
                if call.isGroup, call.participants.count > 1 {
                    Text(verbatim: call.participants.map { $0.name }.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 8)
                }
                if let code = call.verifyCode {
                    verifyCard(code).padding(.top, 18).transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer()
                Group {
                    if call.phase == .ringingIn {
                        IncomingControls(video: call.isVideo, animated: animated)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        ActiveControls()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .offset(y: shown ? 0 : 140)
                .opacity(shown ? 1 : 0)
                .padding(.bottom, 24)
            }
            if let local = call.localVideo, call.isVideo, call.phase != .ringingIn {
                LocalPreview(track: local)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(Safir.spring, value: call.phase)
        .animation(Safir.spring, value: call.verifyCode)
        .animation(.easeInOut(duration: 0.35), value: remoteVideo != nil)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { shown = true }
        }
    }

    private var topBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: call.isGroup ? "person.3.fill" : "lock.fill").font(.system(size: 11, weight: .bold))
            Text(tr(call.isGroup ? "Групповой звонок" : "Сквозное шифрование"))
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.12)))
    }

    private func verifyCard(_ code: String) -> some View {
        VStack(spacing: 4) {
            Text(tr("Код проверки")).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
            Text(verbatim: code)
                .font(.system(size: 20, weight: .semibold, design: .monospaced)).tracking(3)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
    }

    private func status(at now: Date) -> String {
        switch call.phase {
        case .ringingOut: return tr("Вызов…")
        case .ringingIn: return tr(call.isVideo ? "Видеозвонок" : "Входящий звонок")
        case .connecting: return tr("Соединение…")
        case .idle: return tr("Звонок завершён")
        case .active:
            guard let start = call.connectedAt else { return "" }
            let s = Int(now.timeIntervalSince(start))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }
}

/// Deep Safir gradient with soft accent glows drifting behind the content.
private struct CallBackdrop: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Safir.accentDeep, Color(hex: 0x0A1C2A), Color(hex: 0x04090F)],
                               startPoint: .top, endPoint: .bottom)
                glow(Safir.accent, size: 340, x: cos(t / 5) * 90 - 60, y: sin(t / 7) * 70 - 230)
                glow(Safir.accentDeep, size: 300, x: sin(t / 6) * 100 + 90, y: cos(t / 8) * 90 + 110)
                glow(Safir.accent.opacity(0.7), size: 240, x: cos(t / 9) * 70, y: sin(t / 4) * 50 + 340)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, size: CGFloat, x: Double, y: Double) -> some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: 90).opacity(0.5).offset(x: x, y: y)
    }
}

/// Avatar with ripples: quick wide waves while ringing, a slow breath once connected.
private struct CallAvatar: View {
    let name: String
    let path: String?
    let ringing: Bool
    let animated: Bool

    var body: some View {
        ZStack {
            if animated {
                Ripples(ringing: ringing).id(ringing)
            }
            Circle().fill(.white.opacity(0.08)).frame(width: 148, height: 148)
            AvatarView(name: name, path: path, size: 128)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))
                .shadow(color: Safir.accent.opacity(0.55), radius: 30)
        }
        .frame(width: 260, height: 260)
    }
}

private struct Ripples: View {
    let ringing: Bool
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Safir.accent.opacity(ringing ? 0.35 : 0.22))
                    .frame(width: 128, height: 128)
                    .scaleEffect(go ? (ringing ? 2.0 : 1.3) : 1)
                    .opacity(go ? 0 : 1)
                    .animation(.easeOut(duration: ringing ? 2.4 : 3.6)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * (ringing ? 0.8 : 1.2)), value: go)
            }
        }
        .onAppear { go = true }
    }
}

/// Decline / accept, the accept button bouncing like a ringing phone.
private struct IncomingControls: View {
    let video: Bool
    let animated: Bool
    @State private var bounce = false

    var body: some View {
        HStack {
            RoundCallButton(icon: "phone.down.fill", label: "Отклонить",
                            fill: AnyShapeStyle(Color(hex: 0xFF3B30)), size: 74) {
                CallService.shared.hangUp()
            }
            Spacer()
            RoundCallButton(icon: video ? "video.fill" : "phone.fill", label: "Принять",
                            fill: AnyShapeStyle(LinearGradient(colors: [Safir.accent, Safir.accentDeep],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing)),
                            size: 74, glow: true) {
                CallService.shared.answer()
            }
            .offset(y: bounce ? -8 : 0)
            .rotationEffect(.degrees(bounce ? -6 : 6))
            .animation(animated ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : nil, value: bounce)
        }
        .padding(.horizontal, 52)
        .onAppear { bounce = animated }
    }
}

/// Telegram-style row: speaker, camera, microphone, end, on a glass panel.
private struct ActiveControls: View {
    private var call: CallService { CallService.shared }
    private let off = AnyShapeStyle(Color.white.opacity(0.16))
    private let on = AnyShapeStyle(Color.white)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundCallButton(icon: call.speaker ? "speaker.wave.3.fill" : "speaker.fill", label: "Динамик",
                            fill: call.speaker ? on : off, glyph: call.speaker ? .black : .white) {
                call.toggleSpeaker()
            }
            .frame(maxWidth: .infinity)
            if call.localVideo != nil {
                RoundCallButton(icon: call.isVideo ? "video.fill" : "video.slash.fill", label: "Камера",
                                fill: call.isVideo ? on : off, glyph: call.isVideo ? .black : .white) {
                    call.toggleVideo()
                }
                .frame(maxWidth: .infinity)
            }
            RoundCallButton(icon: call.muted ? "mic.slash.fill" : "mic.fill", label: "Микрофон",
                            fill: call.muted ? on : off, glyph: call.muted ? .black : .white) {
                call.toggleMute()
            }
            .frame(maxWidth: .infinity)
            RoundCallButton(icon: "phone.down.fill", label: "Завершить", fill: AnyShapeStyle(Color(hex: 0xFF3B30))) {
                call.hangUp()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16).padding(.horizontal, 8)
        .safirGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

private struct RoundCallButton: View {
    let icon: String
    let label: String
    let fill: AnyShapeStyle
    var glyph: Color = .white
    var size: CGFloat = 58
    var glow = false
    let action: () -> Void

    var body: some View {
        Button {
            Safir.tap(.medium)
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(glyph)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: size, height: size)
                    .background(Circle().fill(fill))
                    .shadow(color: glow ? Safir.accent.opacity(0.6) : .clear, radius: 18)
                Text(tr(label)).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(label)
    }
}

/// Own camera in a corner; drag it and it snaps to the nearest corner.
private struct LocalPreview: View {
    let track: RTCVideoTrack
    @State private var corner = 1 // 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
    @State private var drag = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = 108, h: CGFloat = 160, pad: CGFloat = 16
            let x = corner % 2 == 0 ? pad + w / 2 : geo.size.width - pad - w / 2
            let y = corner < 2 ? 56 + h / 2 : geo.size.height - 200 - h / 2
            VideoTrackView(track: track)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                .position(x: x + drag.width, y: y + drag.height)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            let px = x + value.predictedEndTranslation.width
                            let py = y + value.predictedEndTranslation.height
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                corner = (px < geo.size.width / 2 ? 0 : 1) + (py < geo.size.height / 2 ? 0 : 2)
                                drag = .zero
                            }
                        }
                )
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

/// Renders a WebRTC video track (Metal).
struct VideoTrackView: UIViewRepresentable {
    let track: RTCVideoTrack

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        track.add(view)
        context.coordinator.track = track
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        guard context.coordinator.track !== track else { return }
        context.coordinator.track?.remove(view)
        track.add(view)
        context.coordinator.track = track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var track: RTCVideoTrack?
    }
}
