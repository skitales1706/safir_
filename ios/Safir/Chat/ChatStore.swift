import Foundation

/// Reads and writes chats, members, users and messages in the local database. Synchronous and
/// thread-safe (Database locks); ChatService calls it and bumps its revision for the UI.
final class ChatStore {
    static let shared = ChatStore()
    private let db = Database.shared

    // MARK: Users

    func upsert(users: [APIUser]) {
        try? db.transaction {
            for u in users {
                try db.execute("""
                    INSERT INTO users(id, username, email, full_name, avatar_url, bio, is_online, last_seen, is_bot, is_premium)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET username = excluded.username, email = COALESCE(excluded.email, users.email),
                        full_name = excluded.full_name, avatar_url = excluded.avatar_url, bio = excluded.bio,
                        is_online = excluded.is_online, last_seen = excluded.last_seen,
                        is_bot = excluded.is_bot, is_premium = excluded.is_premium
                    """, [.text(u.id.lowercased()), .text(u.username), .optText(u.email), .text(u.fullName ?? ""),
                          .optText(u.avatarUrl), .optText(u.bio), .bool(u.isOnline ?? false), .optText(u.lastSeen),
                          .bool(u.isBot ?? false), .bool(u.isPremium ?? false)])
            }
        }
    }

    func user(_ id: String) -> APIUser? {
        let found = try? db.first(
            "SELECT id, username, email, full_name, avatar_url, bio, is_online, last_seen, is_bot, is_premium FROM users WHERE id = ?",
            [.text(id.lowercased())]
        ) { r in
            APIUser(id: r.text(0) ?? "", username: r.text(1) ?? "", email: r.text(2), fullName: r.text(3),
                    avatarUrl: r.text(4), bio: r.text(5), isOnline: r.int(6) != 0, lastSeen: r.text(7),
                    isBot: r.int(8) != 0, isPremium: r.int(9) != 0)
        }
        return found ?? nil
    }

    /// Contacts tab: everyone this device knows (chat partners, group members, people added
    /// from search), online first, then by name - like Android's users list.
    func contacts(excluding myUserId: String) -> [APIUser] {
        (try? db.query("""
            SELECT id, username, email, full_name, avatar_url, bio, is_online, last_seen, is_bot, is_premium
            FROM users WHERE id != ? AND is_bot = 0
            ORDER BY is_online DESC, CASE full_name WHEN '' THEN username ELSE full_name END COLLATE NOCASE
            """, [.text(myUserId.lowercased())]) { r in
            APIUser(id: r.text(0) ?? "", username: r.text(1) ?? "", email: r.text(2), fullName: r.text(3),
                    avatarUrl: r.text(4), bio: r.text(5), isOnline: r.int(6) != 0, lastSeen: r.text(7),
                    isBot: r.int(8) != 0, isPremium: r.int(9) != 0)
        }) ?? []
    }

    func displayName(_ userId: String) -> String {
        guard let u = user(userId) else { return "Пользователь" }
        if let name = u.fullName, !name.isEmpty { return name }
        return u.username
    }

    func setOnline(_ userId: String, online: Bool, lastSeen: String?) {
        try? db.execute("UPDATE users SET is_online = ?, last_seen = COALESCE(?, last_seen) WHERE id = ?",
                        [.bool(online), .optText(lastSeen), .text(userId.lowercased())])
    }

    // MARK: Chats

    /// GET /chats result. Server-side previews of E2E chats are ciphertext and never shown - the
    /// local preview (from decrypted messages) is kept; cloud chats take the server's text.
    func sync(chats: [APIChat], myUserId: String) {
        let me = myUserId.lowercased()
        try? db.transaction {
            for c in chats {
                let members = c.members ?? []
                upsert(users: members)
                let partner = c.isGroup ? nil : members.first { $0.id.lowercased() != me }
                let partnerId = partner?.id.lowercased() ?? (c.isGroup || ChatIds.isDirect(c.id) ? nil : c.id.lowercased())
                let localId = c.isGroup ? c.id.lowercased() : (partnerId.map { ChatIds.direct(me, $0) } ?? c.id.lowercased())
                let isChannel = c.isChannel == true
                let isBot = partner?.isBot == true
                let cloud = isChannel || isBot
                let name = c.name ?? partner?.fullName ?? c.partnerName ?? "Чат"
                let myRole = c.memberDetails?.first { $0.userId.lowercased() == me }?.role
                try db.execute("""
                    INSERT INTO chats(id, name, avatar_url, is_group, is_channel, is_bot, partner_id, last_message,
                        last_message_time, last_sender_id, unread_count, group_key_version, ttl_seconds, is_secret,
                        pinned_message_id, description, username, invite_token, subscribers_count, my_role)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, avatar_url = excluded.avatar_url,
                        is_group = excluded.is_group, is_channel = excluded.is_channel, is_bot = excluded.is_bot,
                        partner_id = excluded.partner_id,
                        last_message = CASE WHEN ? THEN excluded.last_message ELSE chats.last_message END,
                        last_message_time = MAX(chats.last_message_time, excluded.last_message_time),
                        unread_count = excluded.unread_count, group_key_version = excluded.group_key_version,
                        ttl_seconds = excluded.ttl_seconds, is_secret = excluded.is_secret,
                        pinned_message_id = COALESCE(excluded.pinned_message_id, chats.pinned_message_id),
                        description = excluded.description,
                        username = excluded.username, invite_token = excluded.invite_token,
                        subscribers_count = excluded.subscribers_count, my_role = excluded.my_role
                    """, [
                        .text(localId), .text(name), .optText(c.avatarUrl ?? partner?.avatarUrl), .bool(c.isGroup),
                        .bool(isChannel), .bool(isBot), .optText(partnerId),
                        .optText(cloud ? c.lastMessage : nil), .int(Dates.millis(c.lastMessageAt)),
                        .optText(c.lastMessageSenderId?.lowercased()), .int(Int64(c.unreadCount ?? 0)),
                        .int(Int64(c.groupKeyVersion ?? 1)), .int(Int64(c.ttlSeconds ?? 0)), .bool(c.isSecret ?? false),
                        .optText(c.pinnedMessageId), .optText(c.description), .optText(c.username),
                        .optText(c.inviteToken), .int(Int64(c.subscribersCount ?? 0)), .optText(myRole),
                        .bool(cloud),
                    ])
                if c.isGroup {
                    try db.execute("DELETE FROM chat_members WHERE chat_id = ?", [.text(localId)])
                    var roles: [String: String] = [:]
                    for d in c.memberDetails ?? [] { roles[d.userId.lowercased()] = d.role }
                    for m in members {
                        let id = m.id.lowercased()
                        try db.execute("INSERT OR REPLACE INTO chat_members(chat_id, user_id, role) VALUES(?, ?, ?)",
                                       [.text(localId), .text(id), .text(roles[id] ?? "member")])
                    }
                }
            }
        }
    }

    /// A 1:1 chat opened from search before any message exists.
    func ensureDirectChat(myUserId: String, partner: APIUser) -> String {
        upsert(users: [partner])
        let id = ChatIds.direct(myUserId, partner.id)
        let name = (partner.fullName?.isEmpty == false ? partner.fullName : nil) ?? partner.username
        try? db.execute("INSERT OR IGNORE INTO chats(id, name, avatar_url, is_group, is_bot, partner_id, last_message_time) VALUES(?, ?, ?, 0, ?, ?, ?)",
                        [.text(id), .text(name), .optText(partner.avatarUrl), .bool(partner.isBot ?? false),
                         .text(partner.id.lowercased()), .int(Clock.nowMs)])
        return id
    }

    func chats() -> [ChatItem] {
        (try? db.query(Self.chatSelect + " ORDER BY last_message_time DESC", [], Self.chatRow)) ?? []
    }

    func chat(_ id: String) -> ChatItem? {
        let found = try? db.first(Self.chatSelect + " WHERE id = ?", [.text(id.lowercased())], Self.chatRow)
        return found ?? nil
    }

    func members(_ chatId: String) -> [String] {
        (try? db.query("SELECT user_id FROM chat_members WHERE chat_id = ?", [.text(chatId.lowercased())]) { $0.text(0) ?? "" }) ?? []
    }

    func memberRoles(_ chatId: String) -> [(userId: String, role: String)] {
        (try? db.query("SELECT user_id, role FROM chat_members WHERE chat_id = ?", [.text(chatId.lowercased())]) {
            (userId: $0.text(0) ?? "", role: $0.text(1) ?? "member")
        }) ?? []
    }

    func deleteChat(_ id: String) {
        try? db.transaction {
            try db.execute("DELETE FROM messages WHERE chat_id = ?", [.text(id)])
            try db.execute("DELETE FROM chat_members WHERE chat_id = ?", [.text(id)])
            try db.execute("DELETE FROM chats WHERE id = ?", [.text(id)])
        }
    }

    func clearMessages(_ chatId: String) {
        try? db.execute("DELETE FROM messages WHERE chat_id = ?", [.text(chatId)])
        try? db.execute("UPDATE chats SET last_message = NULL, unread_count = 0 WHERE id = ?", [.text(chatId)])
    }

    func setPreview(chatId: String, text: String?, time: Int64, senderId: String, status: Int, isRead: Bool,
                    incrementUnread: Bool) {
        try? db.execute("""
            UPDATE chats SET last_message = ?, last_message_time = ?, last_sender_id = ?, last_status = ?,
                last_is_read = ?, unread_count = unread_count + ? WHERE id = ? AND last_message_time <= ?
            """, [.optText(text), .int(time), .text(senderId), .int(Int64(status)), .bool(isRead),
                  .int(incrementUnread ? 1 : 0), .text(chatId), .int(time)])
    }

    func refreshPreview(chatId: String) {
        guard let last = messages(chatId, limit: 1).last else {
            try? db.execute("UPDATE chats SET last_message = NULL WHERE id = ?", [.text(chatId)])
            return
        }
        try? db.execute("UPDATE chats SET last_message = ?, last_sender_id = ?, last_status = ?, last_is_read = ? WHERE id = ?",
                        [.text(Self.preview(last)), .text(last.senderId), .int(Int64(last.deliveryStatus)),
                         .bool(last.isRead), .text(chatId)])
    }

    func resetUnread(_ chatId: String) {
        try? db.execute("UPDATE chats SET unread_count = 0 WHERE id = ?", [.text(chatId)])
    }

    /// Pinned message of a chat, kept on this device like Android's Room column (the server
    /// list sends none, so sync keeps the local value).
    func setPinnedMessage(_ chatId: String, _ messageId: String?) {
        try? db.execute("UPDATE chats SET pinned_message_id = ? WHERE id = ?", [.optText(messageId), .text(chatId)])
    }

    func setChatFlags(_ chatId: String, ttlSeconds: Int? = nil, isSecret: Bool? = nil, isMuted: Bool? = nil, isBot: Bool? = nil) {
        if let ttlSeconds { try? db.execute("UPDATE chats SET ttl_seconds = ? WHERE id = ?", [.int(Int64(ttlSeconds)), .text(chatId)]) }
        if let isSecret { try? db.execute("UPDATE chats SET is_secret = ? WHERE id = ?", [.bool(isSecret), .text(chatId)]) }
        if let isMuted { try? db.execute("UPDATE chats SET is_muted = ? WHERE id = ?", [.bool(isMuted), .text(chatId)]) }
        if let isBot { try? db.execute("UPDATE chats SET is_bot = ? WHERE id = ?", [.bool(isBot), .text(chatId)]) }
    }

    static func preview(_ m: MessageItem) -> String {
        if m.isForwarded { return "[Переслано]" }
        switch m.type {
        case "image": return "📷 Фото"
        case "video": return "🎬 Видео"
        case "audio": return "🎤 Голосовое"
        case "file": return "📎 Файл"
        // "[sticker:<id>]" (UI/Stickers.swift) - a label, not the token.
        case "text" where m.content.hasPrefix("[sticker:") && m.content.hasSuffix("]"): return "Стикер"
        case "text" where SharedContact.parse(m.content) != nil:
            return "👤 " + (SharedContact.parse(m.content)?.name ?? "Контакт")
        default: return m.content
        }
    }

    // MARK: Messages

    func messages(_ chatId: String, limit: Int = 500) -> [MessageItem] {
        let rows = (try? db.query(Self.messageSelect + " WHERE chat_id = ? ORDER BY timestamp DESC LIMIT ?",
                                  [.text(chatId.lowercased()), .int(Int64(limit))], Self.messageRow)) ?? []
        return rows.reversed()
    }

    func message(_ serverId: String) -> MessageItem? {
        let found = try? db.first(Self.messageSelect + " WHERE server_id = ?", [.text(serverId)], Self.messageRow)
        return found ?? nil
    }

    func message(clientId: String) -> MessageItem? {
        let found = try? db.first(Self.messageSelect + " WHERE client_message_id = ?", [.text(clientId)], Self.messageRow)
        return found ?? nil
    }

    func insert(_ m: MessageItem) {
        try? db.execute("""
            INSERT OR IGNORE INTO messages(server_id, client_message_id, chat_id, sender_id, type, content, file_key,
                local_path, thumbnail, protocol_version, timestamp, is_me, delivery_status, is_delivered, is_read,
                reply_to_id, is_forwarded, is_edited, edit_version, ttl_seconds, expires_at, unverified_device,
                reactions, requires_ack, acks, acked, views)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(m.serverId), .optText(m.clientMessageId), .text(m.chatId), .text(m.senderId), .text(m.type),
                  .text(m.content), .optText(m.fileKey), .optText(m.localPath), .optText(m.thumbnail),
                  .int(Int64(m.protocolVersion)), .int(m.timestamp), .bool(m.isMe), .int(Int64(m.deliveryStatus)),
                  .bool(m.isDelivered), .bool(m.isRead), .optText(m.replyToId), .bool(m.isForwarded),
                  .bool(m.isEdited), .int(Int64(m.editVersion)), .int(Int64(m.ttlSeconds)), .int(m.expiresAt),
                  .bool(m.unverifiedDevice), .optText(Self.encodeReactions(m.reactions)), .bool(m.requiresAck),
                  .int(Int64(m.acks)), .bool(m.acked), .int(Int64(m.views))])
    }

    /// The server accepted a send: the TEMP_ row takes the real id. No-op if already done.
    func confirmSent(tempId: String, serverId: String, isDelivered: Bool, isRead: Bool,
                     ttlSeconds: Int = 0, expiresAt: Int64 = 0, content: String? = nil) {
        try? db.transaction {
            if message(serverId) != nil {
                // The WebSocket echo got here first - drop the duplicate pending row.
                if tempId != serverId {
                    try db.execute("DELETE FROM messages WHERE server_id = ?", [.text(tempId)])
                }
                return
            }
            try db.execute("""
                UPDATE messages SET server_id = ?, delivery_status = ?, is_delivered = (is_delivered OR ?),
                    is_read = (is_read OR ?), ttl_seconds = ?, expires_at = ?, content = COALESCE(?, content)
                WHERE server_id = ?
                """, [.text(serverId), .int(Int64(DeliveryStatus.sent)), .bool(isDelivered), .bool(isRead),
                      .int(Int64(ttlSeconds)), .int(expiresAt), .optText(content), .text(tempId)])
        }
    }

    func setStatus(_ serverId: String, _ status: Int) {
        try? db.execute("UPDATE messages SET delivery_status = ? WHERE server_id = ?", [.int(Int64(status)), .text(serverId)])
    }

    @discardableResult
    func markDelivered(_ serverId: String) -> Bool {
        try? db.execute("UPDATE messages SET is_delivered = 1 WHERE server_id = ?", [.text(serverId)])
        return db.changes > 0
    }

    /// The partner read the chat: every message of mine there is read.
    func markMineRead(chatId: String) {
        try? db.execute("UPDATE messages SET is_read = 1, is_delivered = 1 WHERE chat_id = ? AND is_me = 1", [.text(chatId)])
        try? db.execute("UPDATE chats SET last_is_read = 1 WHERE id = ?", [.text(chatId)])
    }

    func markTheirsRead(chatId: String) {
        try? db.execute("UPDATE messages SET is_read = 1 WHERE chat_id = ? AND is_me = 0", [.text(chatId)])
    }

    func delete(_ serverId: String) {
        try? db.execute("DELETE FROM messages WHERE server_id = ?", [.text(serverId)])
    }

    func applyEdit(_ serverId: String, content: String, editVersion: Int) {
        try? db.execute("UPDATE messages SET content = ?, is_edited = 1, edit_version = ? WHERE server_id = ?",
                        [.text(content), .int(Int64(editVersion)), .text(serverId)])
    }

    func attachMedia(_ serverId: String, url: String) {
        try? db.execute("UPDATE messages SET content = ? WHERE server_id = ? AND content = ''", [.text(url), .text(serverId)])
    }

    func setLocalPath(_ serverId: String, path: String?) {
        try? db.execute("UPDATE messages SET local_path = ? WHERE server_id = ?", [.optText(path), .text(serverId)])
    }

    func setExpiry(_ serverId: String, ttlSeconds: Int, expiresAt: Int64) {
        try? db.execute("UPDATE messages SET ttl_seconds = ?, expires_at = ? WHERE server_id = ?",
                        [.int(Int64(ttlSeconds)), .int(expiresAt), .text(serverId)])
    }

    func setReaction(_ serverId: String, userId: String, emoji: String) {
        guard var m = message(serverId) else { return }
        if emoji.isEmpty { m.reactions[userId] = nil } else { m.reactions[userId] = emoji }
        try? db.execute("UPDATE messages SET reactions = ? WHERE server_id = ?",
                        [.optText(Self.encodeReactions(m.reactions)), .text(serverId)])
    }

    /// Bot inline buttons (BotMarkup) - kept beside the message, read by the bubble.
    func setReplyMarkup(_ serverId: String, _ markup: BotMarkup) {
        try? db.execute("UPDATE messages SET reply_markup = ? WHERE server_id = ?", [.optText(markup.json), .text(serverId)])
    }

    func replyMarkup(_ serverId: String) -> BotMarkup? {
        let json = (try? db.query("SELECT reply_markup FROM messages WHERE server_id = ?", [.text(serverId)]) { $0.text(0) })?.first ?? nil
        return BotMarkup.from(json: json)
    }

    func setAck(_ serverId: String, acks: Int, acked: Bool) {
        try? db.execute("UPDATE messages SET acks = ?, acked = ? WHERE server_id = ?", [.int(Int64(acks)), .bool(acked), .text(serverId)])
    }

    func setViews(_ serverId: String, views: Int) {
        try? db.execute("UPDATE messages SET views = MAX(views, ?) WHERE server_id = ?", [.int(Int64(views)), .text(serverId)])
    }

    /// Rows still waiting for the network (sent again after reconnect).
    func pendingMessages() -> [MessageItem] {
        (try? db.query(Self.messageSelect + " WHERE server_id LIKE 'TEMP_%' AND delivery_status = 0 ORDER BY timestamp",
                       [], Self.messageRow)) ?? []
    }

    func expiredMessages(now: Int64) -> [MessageItem] {
        (try? db.query(Self.messageSelect + " WHERE expires_at > 0 AND expires_at <= ?", [.int(now)], Self.messageRow)) ?? []
    }

    func search(_ text: String) -> [MessageItem] {
        (try? db.query(Self.messageSelect + " WHERE type = 'text' AND content LIKE ? ORDER BY timestamp DESC LIMIT 100",
                       [.text("%\(text)%")], Self.messageRow)) ?? []
    }

    // MARK: Row mapping

    private static let chatSelect = """
        SELECT id, name, avatar_url, is_group, is_channel, is_bot, partner_id, last_message, last_message_time,
            last_sender_id, last_status, last_is_read, unread_count, group_key_version, ttl_seconds, is_secret,
            pinned_message_id, description, username, subscribers_count, my_role, is_muted FROM chats
        """

    private static func chatRow(_ r: Row) -> ChatItem {
        ChatItem(id: r.text(0) ?? "", name: r.text(1) ?? "", avatarUrl: r.text(2), isGroup: r.int(3) != 0,
                 isChannel: r.int(4) != 0, isBot: r.int(5) != 0, partnerId: r.text(6), lastMessage: r.text(7),
                 lastMessageTime: r.int(8), lastSenderId: r.text(9), lastStatus: Int(r.int(10)), lastIsRead: r.int(11) != 0,
                 unreadCount: Int(r.int(12)), groupKeyVersion: Int(r.int(13)), ttlSeconds: Int(r.int(14)),
                 isSecret: r.int(15) != 0, pinnedMessageId: r.text(16), description: r.text(17), username: r.text(18),
                 subscribersCount: Int(r.int(19)), myRole: r.text(20), isMuted: r.int(21) != 0)
    }

    private static let messageSelect = """
        SELECT server_id, client_message_id, chat_id, sender_id, type, content, file_key, local_path, thumbnail,
            protocol_version, timestamp, is_me, delivery_status, is_delivered, is_read, reply_to_id, is_forwarded,
            is_edited, edit_version, ttl_seconds, expires_at, unverified_device, reactions, requires_ack, acks,
            acked, views FROM messages
        """

    private static func messageRow(_ r: Row) -> MessageItem {
        MessageItem(serverId: r.text(0) ?? "", clientMessageId: r.text(1), chatId: r.text(2) ?? "", senderId: r.text(3) ?? "",
                    type: r.text(4) ?? "text", content: r.text(5) ?? "", fileKey: r.text(6), localPath: r.text(7),
                    thumbnail: r.text(8), protocolVersion: Int(r.int(9)), timestamp: r.int(10), isMe: r.int(11) != 0,
                    deliveryStatus: Int(r.int(12)), isDelivered: r.int(13) != 0, isRead: r.int(14) != 0,
                    replyToId: r.text(15), isForwarded: r.int(16) != 0, isEdited: r.int(17) != 0,
                    editVersion: Int(r.int(18)), ttlSeconds: Int(r.int(19)), expiresAt: r.int(20),
                    unverifiedDevice: r.int(21) != 0, reactions: decodeReactions(r.text(22)),
                    requiresAck: r.int(23) != 0, acks: Int(r.int(24)), acked: r.int(25) != 0, views: Int(r.int(26)))
    }

    private static func encodeReactions(_ r: [String: String]) -> String? {
        guard !r.isEmpty, let data = try? JSONSerialization.data(withJSONObject: r) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeReactions(_ s: String?) -> [String: String] {
        guard let s, let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj
    }
}
