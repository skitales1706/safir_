import Foundation

// MARK: - Wire models (backend schemas.py; snake_case converted by APIClient)

struct APIUser: Codable, Hashable {
    let id: String
    let username: String
    let email: String?
    let fullName: String?
    let avatarUrl: String?
    let bio: String?
    let isOnline: Bool?
    let lastSeen: String?
    let isBot: Bool?
    let isPremium: Bool?
}

struct APIMemberDetail: Decodable {
    let userId: String
    let role: String
}

struct APIChat: Decodable {
    let id: String
    let name: String?
    let avatarUrl: String?
    let isGroup: Bool
    let lastMessage: String?
    let lastMessageAt: String?
    let lastMessageProtocol: Int?
    let lastMessageSenderId: String?
    let groupKeyVersion: Int?
    let members: [APIUser]?
    let unreadCount: Int?
    let partnerName: String?
    let memberDetails: [APIMemberDetail]?
    let pinnedMessageId: String?
    let ttlSeconds: Int?
    let isSecret: Bool?
    let isChannel: Bool?
    let description: String?
    let username: String?
    let inviteToken: String?
    let subscribersCount: Int?
}

struct APIMessage: Decodable {
    let id: String
    let chatId: String
    let senderId: String
    let content: String
    let encryptedKey: String?
    let ratchetContents: [String: String]?
    let senderDeviceId: Int?
    let protocolVersion: Int?
    let protocolVersionSender: Int?
    let groupKeyVersion: Int?
    let type: String
    let isDelivered: Bool?
    let isRead: Bool?
    let createdAt: String
    let replyToId: String?
    let isEdited: Bool?
    let editVersion: Int?
    let isForwarded: Bool?
    let views: Int?
    let requiresAck: Bool?
    let acks: Int?
    let ttlSeconds: Int?
    let expiresAt: String?
    let clientMessageId: String?
    let thumbnail: String?
    let replyMarkup: BotMarkup?
}

/// Inline buttons under a bot message (backend bots.validate_reply_markup, Telegram's
/// InlineKeyboardMarkup): a button either sends `callback_data` to the bot or opens `url`.
struct BotMarkup: Codable, Equatable {
    struct Button: Codable, Equatable {
        let text: String
        let callbackData: String?
        let url: String?
    }
    let inlineKeyboard: [[Button]]

    /// Stored in the local DB as JSON (camelCase - our own format, not the wire one).
    var json: String? { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } }

    static func from(json: String?) -> BotMarkup? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BotMarkup.self, from: data)
    }

    /// From a WebSocket event's `reply_markup` dictionary (snake_case wire format).
    static func from(wire: Any?) -> BotMarkup? {
        guard let wire, JSONSerialization.isValidJSONObject(wire),
              let data = try? JSONSerialization.data(withJSONObject: wire) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(BotMarkup.self, from: data)
    }
}

struct SyncChatInfo: Decodable {
    let isGroup: Bool
    let memberIds: [String]
}

struct SyncResponse: Decodable {
    let messages: [APIMessage]
    let chats: [String: SyncChatInfo]
    let serverTime: String
}

struct SyncRequest: Encodable {
    let since: String?
}

struct ChatFocusRequest: Encodable {
    let targetId: String?
}

struct MessageRequest: Encodable {
    let content: String
    let type: String
    let clientMessageId: String
    var encryptedKey: String?
    var ratchetContents: [String: String]?
    var senderDeviceId: Int?
    var protocolVersion: Int
    var protocolVersionSender: Int
    var groupKeyVersion: Int?
    var replyToId: String?
    var isForwarded: Bool
    var thumbnail: String?
    var requiresAck: Bool?
    var archive: String?
}

struct EditMessageRequest: Encodable {
    let content: String
    let ratchetContents: [String: String]?
    let senderDeviceId: Int
    let protocolVersion: Int
    let protocolVersionSender: Int
    let archive: String?
}

struct AttachMediaRequest: Encodable {
    let content: String
}

struct CreateGroupRequest: Encodable {
    let name: String
    let memberIds: [String]
    let isChannel: Bool
}

/// One incoming message in a shape shared by the WebSocket event, REST history and /sync.
struct IncomingMessage {
    var id: String
    var clientMessageId: String?
    var serverChatId: String
    var isGroup: Bool
    /// The other party of a 1:1 (for my own echoes this is the recipient).
    var partnerId: String?
    var senderId: String
    var content: String
    var encryptedKey: String?
    var ratchetContents: [String: String]?
    var senderDeviceId: Int?
    var protocolVersion: Int
    var type: String
    var timestamp: Int64
    var isDelivered: Bool
    var isRead: Bool
    var replyToId: String?
    var isForwarded: Bool
    var editVersion: Int
    var ttlSeconds: Int
    var expiresAt: Int64
    var thumbnail: String?
    var requiresAck: Bool
    var acks: Int
    var views: Int
    var replyMarkup: BotMarkup? = nil
}

// MARK: - Local models (rows of the local database)

struct ChatItem: Identifiable, Hashable {
    let id: String
    var name: String
    var avatarUrl: String?
    var isGroup: Bool
    var isChannel: Bool
    var isBot: Bool
    var partnerId: String?
    var lastMessage: String?
    var lastMessageTime: Int64
    var lastSenderId: String?
    var lastStatus: Int
    var lastIsRead: Bool
    var unreadCount: Int
    var groupKeyVersion: Int
    var ttlSeconds: Int
    var isSecret: Bool
    var pinnedMessageId: String?
    var description: String?
    var username: String?
    var subscribersCount: Int
    var myRole: String?
    var isMuted: Bool

    /// Cloud chat (not end-to-end): a channel, or a 1:1 chat with a bot.
    var isCloud: Bool { isChannel || isBot }
}

struct MessageItem: Identifiable, Hashable {
    var id: String { serverId }
    var serverId: String
    var clientMessageId: String?
    var chatId: String
    var senderId: String
    var type: String
    var content: String
    var fileKey: String?
    var localPath: String?
    var thumbnail: String?
    var protocolVersion: Int
    var timestamp: Int64
    var isMe: Bool
    var deliveryStatus: Int
    var isDelivered: Bool
    var isRead: Bool
    var replyToId: String?
    var isForwarded: Bool
    var isEdited: Bool
    var editVersion: Int
    var ttlSeconds: Int
    var expiresAt: Int64
    var unverifiedDevice: Bool
    var reactions: [String: String]
    var requiresAck: Bool
    var acks: Int
    var acked: Bool
    var views: Int

    var isPending: Bool { serverId.hasPrefix("TEMP_") }
}

enum DeliveryStatus {
    static let sending = 0
    static let sent = 1
    static let failed = 2
}

enum Placeholder {
    /// Never show raw server content for a message that should have been end-to-end encrypted.
    static let undecryptable = "🔒 Не удалось расшифровать сообщение"
    static let legacy = "🔒 Сообщение в старом шифровании (не поддерживается)"
}

enum ChatIds {
    /// 1:1 chats are keyed locally by the sorted pair of user ids (same as Android/web).
    static func direct(_ a: String, _ b: String) -> String {
        let x = a.lowercased(), y = b.lowercased()
        return x < y ? "\(x)_\(y)" : "\(y)_\(x)"
    }

    /// What the REST API takes as a chat target: the partner's user id for 1:1, else the chat id.
    static func apiTarget(_ chatId: String, myUserId: String) -> String {
        let id = chatId.lowercased()
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count == 2 else { return id }
        return parts[0] == myUserId.lowercased() ? parts[1] : parts[0]
    }

    static func isDirect(_ chatId: String) -> Bool { chatId.contains("_") }
}

enum Dates {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Backend timestamps are UTC ISO-8601, with or without fraction / "Z" / "+00:00".
    static func millis(_ iso: String?) -> Int64 {
        guard var s = iso, !s.isEmpty else { return 0 }
        s = s.replacingOccurrences(of: " ", with: "T")
        if let plus = s.range(of: "+", options: .backwards) { s = String(s[..<plus.lowerBound]) }
        if s.hasSuffix("Z") { s.removeLast() }
        if let dot = s.firstIndex(of: ".") { s = String(s[..<dot]) }
        guard let date = formatter.date(from: s) else { return Clock.nowMs }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    static func iso(_ millis: Int64) -> String {
        formatter.string(from: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
    }
}

/// "Share contact" (Android SharedContact.kt, Telegram's contact card): an ordinary end-to-end
/// encrypted text message, readable by old builds and the web, with a trailing
/// safir://contact/<user id> line that the apps turn into a card (UI/ChatAttachments.swift).
struct SharedContact: Equatable {
    let userId: String
    let name: String
    let username: String

    private static let scheme = "safir://contact/"

    static func text(userId: String, name: String, username: String) -> String {
        var s = "👤 " + name.trimmingCharacters(in: .whitespaces) + "\n"
        let u = username.trimmingCharacters(in: .whitespaces)
        if !u.isEmpty { s += "@" + u + "\n" }
        return s + scheme + userId.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func parse(_ text: String) -> SharedContact? {
        guard text.hasPrefix("👤 ") else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard let last = lines.last?.trimmingCharacters(in: .whitespaces), last.hasPrefix(scheme) else { return nil }
        let id = String(last.dropFirst(scheme.count)).lowercased()
        guard id.count == 36, UUID(uuidString: id) != nil else { return nil }
        let name = String(lines[0].dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let username = lines.count > 2 && lines[1].hasPrefix("@") ? String(lines[1].dropFirst()) : ""
        return SharedContact(userId: id, name: name, username: username)
    }
}
