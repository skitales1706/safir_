import Foundation
import LiveKit
import Observation

/// Group video meetings on the organisation's SFU (backend routers/meetings.py, DEPLOYMENT.md §16,
/// Android MeetingActivity.kt). The backend hands out a LiveKit token for the chat's room; media
/// goes phone <-> the organisation's LiveKit server (DTLS-SRTP, not end-to-end like 1:1 calls).
/// Not configured on the server -> 503 meetings_unavailable and the app falls back to a call.
@MainActor
@Observable
final class MeetingService {
    static let shared = MeetingService()

    enum JoinResult { case joined, unavailable, failed }

    private(set) var room: Room?
    private(set) var chatId: String?
    private(set) var title = ""
    var showUI = false
    /// Chats where someone started a meeting (meeting_started / GET status) - the "join" banner.
    private(set) var active: Set<String> = []

    private init() {}

    private struct Token: Decodable { let url: String; let token: String; let room: String }
    private struct Status: Decodable { let active: Bool }

    func join(chat: ChatItem, video: Bool = true) async -> JoinResult {
        if room != nil, chatId == chat.id {
            showUI = true
            return .joined
        }
        await leave()
        let api = Session.shared.api
        let token: Token
        do {
            let data = try await api.send("POST", "chats/\(chat.id)/meeting", body: nil)
            token = try api.decode(Token.self, from: data)
        } catch let e as APIError where e.status == 503 {
            return .unavailable
        } catch {
            AppLog.write("Meeting token failed: \(error.localizedDescription)")
            return .failed
        }
        let room = Room(roomOptions: RoomOptions(adaptiveStream: true, dynacast: true))
        do {
            try await room.connect(url: token.url, token: token.token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if video { try await room.localParticipant.setCamera(enabled: true) }
        } catch {
            AppLog.write("Meeting connect failed: \(error.localizedDescription)")
            await room.disconnect()
            return .failed
        }
        self.room = room
        chatId = chat.id
        title = chat.name
        active.insert(chat.id)
        showUI = true
        return .joined
    }

    func leave() async {
        guard let room else { return }
        self.room = nil
        chatId = nil
        showUI = false
        await room.disconnect()
    }

    func toggleMicrophone() async {
        guard let p = room?.localParticipant else { return }
        _ = try? await p.setMicrophone(enabled: !p.isMicrophoneEnabled())
    }

    func toggleCamera() async {
        guard let p = room?.localParticipant else { return }
        _ = try? await p.setCamera(enabled: !p.isCameraEnabled())
    }

    func switchCamera() async {
        guard let track = room?.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer else { return }
        _ = try? await capturer.switchCameraPosition()
    }

    // MARK: - "… начал видеовстречу"

    /// WebSocket meeting_started (server-originated): banner + "join" in that chat.
    func started(_ e: [String: Any]) {
        guard let id = (e["chat_id"] as? String)?.lowercased() else { return }
        active.insert(id)
        guard chatId != id, let chat = ChatStore.shared.chat(id) else { return }
        let by = (e["by_name"] as? String) ?? ""
        Notifier.shared.incoming(chat: chat, senderName: nil, preview: by.isEmpty ? "Началась видеовстреча" : "\(by) начал видеовстречу")
    }

    /// Whether a meeting is going on in this chat (GET /chats/{id}/meeting).
    func refreshStatus(chatId: String) async {
        guard let data = try? await Session.shared.api.send("GET", "chats/\(chatId)/meeting", body: nil),
              let status = try? Session.shared.api.decode(Status.self, from: data) else { return }
        if status.active { active.insert(chatId) } else if self.chatId != chatId { active.remove(chatId) }
    }
}
