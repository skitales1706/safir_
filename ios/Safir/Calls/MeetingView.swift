import LiveKit
import SwiftUI

/// The meeting screen: a grid of participant tiles, mic / camera / flip / leave. DLP applies here
/// too - the watermark, and the content is hidden while the screen is recorded under a ban.
struct MeetingView: View {
    @ObservedObject var room: Room
    let title: String

    private var tiles: [Participant] {
        [room.localParticipant as Participant] + room.remoteParticipants.values.sorted {
            ($0.name ?? "") < ($1.name ?? "")
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text("Участников: \(tiles.count)").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 8)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tiles.count > 4 ? 110 : 160), spacing: 8)], spacing: 8) {
                        ForEach(tiles, id: \.self) { p in
                            MeetingTile(participant: p, isLocal: p is LocalParticipant)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                controls
            }
            if AppSecurity.shared.policy.watermark {
                WatermarkOverlay(text: ChatStore.shared.displayName(ChatService.shared.myUserId))
            }
            if AppSecurity.shared.hideContent {
                PrivacyCover(showUnlock: false)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private var controls: some View {
        let local = room.localParticipant
        return HStack(spacing: 22) {
            round(local.isMicrophoneEnabled() ? "mic.fill" : "mic.slash.fill", on: local.isMicrophoneEnabled()) {
                Task { await MeetingService.shared.toggleMicrophone() }
            }
            round(local.isCameraEnabled() ? "video.fill" : "video.slash.fill", on: local.isCameraEnabled()) {
                Task { await MeetingService.shared.toggleCamera() }
            }
            round("arrow.triangle.2.circlepath.camera", on: true) {
                Task { await MeetingService.shared.switchCamera() }
            }
            Button {
                Task { await MeetingService.shared.leave() }
            } label: {
                Image(systemName: "phone.down.fill").font(.title2).foregroundStyle(.white)
                    .frame(width: 64, height: 64).background(Circle().fill(Color.red))
            }
        }
        .padding(.bottom, 24)
    }

    private func round(_ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(on ? Color.white : Color.black)
                .frame(width: 56, height: 56)
                .background(Circle().fill(on ? Color.white.opacity(0.18) : Color.white))
        }
    }
}

private struct MeetingTile: View {
    @ObservedObject var participant: Participant
    let isLocal: Bool

    private var name: String {
        if isLocal { return "Вы" }
        if let n = participant.name, !n.isEmpty { return n }
        return "Участник"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08))
            if let track = participant.firstCameraVideoTrack, participant.isCameraEnabled() {
                SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: isLocal ? .mirror : .off)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                AvatarView(name: name, path: nil, size: 64).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                if !participant.isMicrophoneEnabled() { Image(systemName: "mic.slash.fill") }
                Text(name).lineLimit(1)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(6)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Safir.accent, lineWidth: participant.isSpeaking ? 3 : 0))
    }
}
