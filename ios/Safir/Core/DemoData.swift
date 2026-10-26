import Foundation

/// Screenshot / design-review mode (launch argument -SafirScreenshots): fills the local database
/// with made-up chats and shows them without any server. Never active in normal use.
enum DemoData {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("-SafirScreenshots") }
    static var loggedOut: Bool { ProcessInfo.processInfo.arguments.contains("-SafirLoggedOut") }

    static let me = UserDTO(id: "u-me", username: "murtazo", email: "demo@safir.tj", fullName: "Муртазо")

    private static func user(_ id: String, _ name: String, online: Bool = false) -> APIUser {
        APIUser(id: id, username: id, email: nil, fullName: name, avatarUrl: nil, bio: nil, isOnline: online,
                lastSeen: nil, isBot: false, isPremium: false)
    }

    private static func chat(_ id: String, _ name: String?, group: Bool, members: [APIUser], channel: Bool = false,
                             unread: Int = 0, subscribers: Int = 0) -> APIChat {
        APIChat(id: id, name: name, avatarUrl: nil, isGroup: group, lastMessage: nil, lastMessageAt: nil,
                lastMessageProtocol: 6, lastMessageSenderId: nil, groupKeyVersion: 1, members: members,
                unreadCount: unread, partnerName: nil, memberDetails: nil, pinnedMessageId: nil, ttlSeconds: 0,
                isSecret: false, isChannel: channel, description: nil, username: nil, inviteToken: nil,
                subscribersCount: subscribers)
    }

    @MainActor
    static func seed() {
        let db = Database.shared
        try? Schema.wipeAccountData(db)
        let store = ChatStore.shared
        let meUser = user(me.id, me.fullName ?? "")
        let amina = user("u-amina", "Амина Саидова", online: true)
        let farhod = user("u-farhod", "Фарход Назаров")
        let nilufar = user("u-nilufar", "Нилуфар Каримова", online: true)
        let rustam = user("u-rustam", "Рустам Алиев")

        store.sync(chats: [
            chat("u-amina", nil, group: false, members: [meUser, amina]),
            chat("g-school", "Мактаби №1 — учителя", group: true, members: [meUser, farhod, nilufar, rustam], unread: 3),
            chat("u-farhod", nil, group: false, members: [meUser, farhod], unread: 1),
            chat("c-news", "Новости школы", group: true, members: [meUser], channel: true, subscribers: 214),
            chat("u-nilufar", nil, group: false, members: [meUser, nilufar]),
        ], myUserId: me.id)

        let now = Clock.nowMs
        let minute: Int64 = 60_000
        var n = 0
        func add(_ chatId: String, _ sender: String, _ text: String, ago: Int64, read: Bool = true,
                 reply: String? = nil, reactions: [String: String] = [:]) {
            n += 1
            let item = MessageItem(
                serverId: "demo-\(n)", clientMessageId: nil, chatId: chatId, senderId: sender, type: "text", content: text,
                fileKey: nil, localPath: nil, thumbnail: nil, protocolVersion: 6, timestamp: now - ago * minute,
                isMe: sender == me.id, deliveryStatus: DeliveryStatus.sent, isDelivered: true, isRead: read,
                replyToId: reply, isForwarded: false, isEdited: false, editVersion: 0, ttlSeconds: 0,
                expiresAt: 0, unverifiedDevice: false, reactions: reactions, requiresAck: false, acks: 0, acked: false,
                views: chatId == "c-news" ? 187 : 0)
            store.insert(item)
            store.setPreview(chatId: item.chatId, text: ChatStore.preview(item), time: item.timestamp, senderId: sender,
                             status: DeliveryStatus.sent, isRead: read, incrementUnread: false)
        }

        let a = ChatIds.direct(me.id, "u-amina")
        add(a, "u-amina", "Ассалому алейкум! Вы получили расписание на следующую неделю?", ago: 60 * 26)
        add(a, me.id, "Ваалейкум ассалом! Да, получил, спасибо 🙏", ago: 60 * 26 - 2)
        add(a, "u-amina", "Отлично. В четверг педсовет в 14:00", ago: 42)
        add(a, "u-amina", "Не забудьте отчёт по успеваемости 📊", ago: 41)
        add(a, me.id, "Конечно, подготовлю к среде", ago: 30, reply: "demo-3", reactions: ["u-amina": "👍"])
        add(a, me.id, "И презентацию тоже пришлю", ago: 29)
        add(a, "u-amina", "Супер, спасибо! 😊", ago: 3, reactions: [me.id: "❤️"])

        let g = "g-school"
        add(g, "u-farhod", "Коллеги, завтра открытый урок в 7«Б»", ago: 95)
        add(g, "u-nilufar", "Я приду 👍", ago: 90)
        add(g, "u-nilufar", "Можно взять проектор из кабинета информатики?", ago: 89)
        add(g, me.id, "Да, ключ у меня, заберите после 3-го урока", ago: 70)
        add(g, "u-rustam", "Напоминаю: родительское собрание в пятницу в 17:00", ago: 12, read: false,
            reactions: ["u-farhod": "👍", "u-nilufar": "👍"])
        add(g, "u-farhod", "Принято", ago: 8, read: false)

        let f = ChatIds.direct(me.id, "u-farhod")
        add(f, "u-farhod", "Можете заменить меня во вторник на 2-м уроке?", ago: 15, read: false)

        add("c-news", "u-rustam", "🎉 Наши ученики заняли 1 место на республиканской олимпиаде по математике!", ago: 300)
        add("c-news", "u-rustam", "С 1 ноября каникулы. Хорошего отдыха всем!", ago: 55)

        let ni = ChatIds.direct(me.id, "u-nilufar")
        add(ni, me.id, "Нилуфар, пришлите, пожалуйста, список класса", ago: 60 * 50)
        add(ni, "u-nilufar", "Уже отправила на почту ✉️", ago: 60 * 49)

        // Contacts without a chat yet (people added from search).
        store.upsert(users: [user("u-dilnoza", "Дилноза Рахимова", online: true), user("u-bakhtiyor", "Бахтиёр Шарипов"),
                             user("u-zarina", "Зарина Холова")])

        // Calls tab: [peer, outgoing, video, status, seconds, minutes ago, seen].
        let calls: [(String, Bool, Bool, String, Int, Int64, Bool)] = [
            ("u-farhod", false, false, CallLogEntry.missed, 0, 14, false),
            ("u-amina", true, true, CallLogEntry.ok, 312, 95, true),
            ("u-nilufar", false, false, CallLogEntry.ok, 47, 60 * 5, true),
            ("u-rustam", true, false, CallLogEntry.cancelled, 0, 60 * 26, true),
            ("u-amina", false, false, CallLogEntry.declined, 0, 60 * 30, true),
            ("u-dilnoza", true, false, CallLogEntry.ok, 1_380, 60 * 52, true),
        ]
        for (i, c) in calls.enumerated() {
            try? db.execute("""
                INSERT INTO call_log(id, peer_id, chat_id, outgoing, video, status, duration, timestamp, seen)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text("demo-call-\(i)"), .text(c.0), .text(ChatIds.direct(me.id, c.0)), .bool(c.1), .bool(c.2),
                      .text(c.3), .int(Int64(c.4)), .int(now - c.5 * minute), .bool(c.6)])
        }
        CallLog.shared.refreshBadge()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-SafirDemoCall"), i + 1 < args.count {
            CallService.shared.startDemo(active: args[i + 1] == "active")
        }
    }
}
