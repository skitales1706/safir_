import Foundation
import UserNotifications

/// Message notification switches from Settings → Notifications. Kept in the App Group so the
/// Notification Service Extension honours them for the banners it builds in the background.
enum NotificationPrefs {
    private static var defaults: UserDefaults { UserDefaults(suiteName: "group.tj.safir.messenger") ?? .standard }

    /// Sender and text in the banner; off = "Новое сообщение" only (Telegram's "Show preview").
    static var preview: Bool {
        get { defaults.object(forKey: "notif_preview") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notif_preview") }
    }

    static var sound: Bool {
        get { defaults.object(forKey: "notif_sound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notif_sound") }
    }

    /// Banners while the app is open on another screen.
    static var inApp: Bool {
        get { defaults.object(forKey: "notif_in_app") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notif_in_app") }
    }

    /// Per chat type, like Telegram's "Private chats / Groups / Channels".
    static var privateChats: Bool {
        get { defaults.object(forKey: "notif_private") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notif_private") }
    }

    static var groups: Bool {
        get { defaults.object(forKey: "notif_groups") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notif_groups") }
    }

    static var channels: Bool {
        get { defaults.object(forKey: "notif_channels") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notif_channels") }
    }

    static func enabled(isGroup: Bool, isChannel: Bool) -> Bool {
        isChannel ? channels : (isGroup ? groups : privateChats)
    }

    /// A push the extension cannot drop (no filtering entitlement): delivered without sound and
    /// without lighting the screen - it only lands in Notification Center.
    static func quiet(_ content: UNMutableNotificationContent) {
        content.sound = nil
        content.interruptionLevel = .passive
    }

    /// Global switches, then the chat's own (chat id from userInfo["chat_id"]).
    static func apply(to content: UNMutableNotificationContent) {
        let chatId = content.userInfo["chat_id"] as? String
        let chat = chatId.map(ChatPrefs.init)
        if !(chat?.preview ?? preview) {
            content.title = "Safir"
            content.subtitle = ""
            content.body = "Новое сообщение"
        }
        if !(chat?.sound ?? sound) { content.sound = nil }
        if let chatId, mutedNow(chatId) { quiet(content) }
    }

    // MARK: Per chat (Telegram's chat notifications: mute for a while, sound, preview)

    struct ChatPrefs {
        /// nil = follow the global switch.
        var sound: Bool?
        var preview: Bool?
        /// Seconds since 1970; 0 = not muted for a time.
        var mutedUntil: Double = 0

        init(sound: Bool? = nil, preview: Bool? = nil, mutedUntil: Double = 0) {
            self.sound = sound
            self.preview = preview
            self.mutedUntil = mutedUntil
        }

        init(_ chatId: String) {
            let d = NotificationPrefs.defaults.dictionary(forKey: "chat_notif_" + chatId) ?? [:]
            sound = d["sound"] as? Bool
            preview = d["preview"] as? Bool
            mutedUntil = d["muted_until"] as? Double ?? 0
        }
    }

    static func chat(_ chatId: String) -> ChatPrefs { ChatPrefs(chatId) }

    static func setChat(_ chatId: String, _ p: ChatPrefs) {
        var d: [String: Any] = [:]
        if let s = p.sound { d["sound"] = s }
        if let v = p.preview { d["preview"] = v }
        if p.mutedUntil > Date().timeIntervalSince1970 { d["muted_until"] = p.mutedUntil }
        if d.isEmpty { defaults.removeObject(forKey: "chat_notif_" + chatId) } else { defaults.set(d, forKey: "chat_notif_" + chatId) }
    }

    /// Muted for a while and the time has not run out yet.
    static func mutedNow(_ chatId: String) -> Bool {
        ChatPrefs(chatId).mutedUntil > Date().timeIntervalSince1970
    }

    /// One line for the chat's profile row.
    static func summary(_ chatId: String, muted: Bool) -> String {
        if muted { return "Выключены" }
        let p = ChatPrefs(chatId)
        if p.mutedUntil > Date().timeIntervalSince1970 {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return "До " + f.string(from: Date(timeIntervalSince1970: p.mutedUntil))
        }
        return p.sound == false ? "Без звука" : "Включены"
    }
}
