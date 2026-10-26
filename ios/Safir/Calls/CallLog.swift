import Foundation
import Observation

/// One finished 1:1 call. Same fields as Android's util/CallLog.kt entry.
struct CallLogEntry: Identifiable, Hashable {
    static let ok = "ok", missed = "missed", declined = "declined", cancelled = "cancelled"

    let id: String
    let peerId: String
    let chatId: String
    let outgoing: Bool
    let video: Bool
    let status: String
    let duration: Int
    let timestamp: Int64

    var isMissed: Bool { !outgoing && (status == Self.missed || status == Self.declined) }

    /// "Исходящий" / "Пропущенный видеозвонок"... - the subtitle Telegram shows in the list.
    var title: String {
        let kind: String
        if isMissed {
            kind = status == Self.declined ? "Отклонённый" : "Пропущенный"
        } else if outgoing {
            kind = status == Self.cancelled ? "Отменённый" : "Исходящий"
        } else {
            kind = "Входящий"
        }
        return video ? "\(kind) видеозвонок" : kind
    }

    /// "12 сек" / "5 мин" / "1:02:03", empty when the call never connected.
    var durationText: String {
        if duration < 1 { return "" }
        if duration < 60 { return "\(duration) сек" }
        if duration < 3600 { return "\(duration / 60) мин" }
        return String(format: "%d:%02d:%02d", duration / 3600, (duration / 60) % 60, duration % 60)
    }
}

/// Telegram-style call log, kept on this device only (the server never stores call history).
/// CallService records each finished 1:1 call; the Calls tab lists them and the tab bar shows
/// unseen missed calls as a red badge.
@MainActor
@Observable
final class CallLog {
    static let shared = CallLog()

    private(set) var revision = 0
    private(set) var unseenMissed = 0
    @ObservationIgnored private let db = Database.shared

    private init() {
        refreshBadge()
    }

    func entries() -> [CallLogEntry] {
        (try? db.query("""
            SELECT id, peer_id, chat_id, outgoing, video, status, duration, timestamp
            FROM call_log ORDER BY timestamp DESC LIMIT 500
            """) { r in
            CallLogEntry(id: r.text(0) ?? "", peerId: r.text(1) ?? "", chatId: r.text(2) ?? "",
                         outgoing: r.int(3) != 0, video: r.int(4) != 0, status: r.text(5) ?? CallLogEntry.ok,
                         duration: Int(r.int(6)), timestamp: r.int(7))
        }) ?? []
    }

    func record(peerId: String, outgoing: Bool, video: Bool, status: String, duration: Int, at: Int64 = Clock.nowMs) {
        let me = ChatService.shared.myUserId
        let peer = peerId.lowercased()
        let missed = !outgoing && (status == CallLogEntry.missed || status == CallLogEntry.declined)
        try? db.execute("""
            INSERT INTO call_log(id, peer_id, chat_id, outgoing, video, status, duration, timestamp, seen)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(UUID().uuidString.lowercased()), .text(peer), .text(ChatIds.direct(me, peer)),
                  .bool(outgoing), .bool(video), .text(status), .int(Int64(duration)), .int(at), .bool(!missed)])
        changed()
    }

    func delete(_ id: String) {
        try? db.execute("DELETE FROM call_log WHERE id = ?", [.text(id)])
        changed()
    }

    func clear() {
        try? db.execute("DELETE FROM call_log")
        changed()
    }

    /// Opening the Calls tab clears the missed-call badge.
    func markSeen() {
        guard unseenMissed > 0 else { return }
        try? db.execute("UPDATE call_log SET seen = 1 WHERE seen = 0")
        changed()
    }

    /// After sign-in / sign-out the table belongs to another account.
    func refreshBadge() {
        unseenMissed = Int((try? db.first("SELECT COUNT(*) FROM call_log WHERE seen = 0") { $0.int(0) }) ?? 0)
    }

    private func changed() {
        refreshBadge()
        revision &+= 1
    }
}
