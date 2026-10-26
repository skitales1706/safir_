import Foundation
import UserNotifications

/// Wakes on the content-free APNs push (backend apns.py: "Новое сообщение", mutable-content),
/// pulls /sync from OUR server, decrypts with the same Signal sessions as the app (shared App
/// Group database + Keychain) and rewrites the banner with the real sender and text. Nothing
/// readable ever passes through Apple.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var task: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        self.content = content
        task = Task { [weak self] in
            await self?.fill(content)
            self?.finish()
        }
    }

    /// iOS gives the extension ~30 seconds; whatever we have by then is shown.
    override func serviceExtensionTimeWillExpire() {
        task?.cancel()
        finish()
    }

    private func finish() {
        guard let handler = contentHandler, let content else { return }
        contentHandler = nil
        NotificationPrefs.apply(to: content)
        handler(content)
    }

    private func fill(_ content: UNMutableNotificationContent) async {
        // Several accounts on the phone (app Accounts.swift): only the active one's sessions are
        // here to decrypt with - for another account just say which one got a message.
        if let target = (content.userInfo["uid"] as? String)?.lowercased(),
           let active = Keychain.get("account_id"), target != active {
            struct Stored: Decodable { let id: String; let name: String }
            let accounts = Keychain.get("accounts")?.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode([Stored].self, from: $0) } ?? []
            content.title = accounts.first { $0.id == target }?.name ?? "Safir"
            content.body = "Новое сообщение"
            content.userInfo["account_id"] = target
            return
        }
        guard let token = Keychain.get("auth_token"), let installId = Keychain.get("device_id"),
              let userJSON = Keychain.get("user")?.data(using: .utf8),
              let user = try? JSONDecoder().decode(UserDTO.self, from: userJSON) else { return }
        let api = APIClient.shared
        api.token = token
        let email = user.email ?? ""
        await SignalService.shared.configure(email: email.isEmpty ? user.id : email)

        let processor = MessageProcessor(myUserId: user.id, installId: installId) {
            if let chats = try? await api.get("chats", as: [APIChat].self) {
                ChatStore.shared.sync(chats: chats, myUserId: user.id)
            }
        }
        do {
            let since = Database.shared.string("last_sync_at")
            let body = try await api.send("POST", "sync", body: SyncRequest(since: since))
            let response = try api.decode(SyncResponse.self, from: body)
            var fresh: [(message: MessageItem, chat: ChatItem?)] = []
            for item in processor.incoming(from: response) {
                if Task.isCancelled { break }
                let result = await processor.process(item, activeChatId: nil)
                if let inserted = result.inserted, !inserted.isMe {
                    fresh.append((message: inserted, chat: result.chat ?? ChatStore.shared.chat(inserted.chatId)))
                }
            }
            Database.shared.set(response.serverTime, for: "last_sync_at")

            guard let newest = fresh.last else { return }
            let preview = ChatStore.preview(newest.message)
            if let chat = newest.chat {
                content.title = chat.name
                content.body = chat.isGroup && !chat.isChannel
                    ? "\(ChatStore.shared.displayName(newest.message.senderId)): \(preview)"
                    : preview
                content.threadIdentifier = chat.id
                content.userInfo["chat_id"] = chat.id
                if chat.isMuted { content.sound = nil }
                if !NotificationPrefs.enabled(isGroup: chat.isGroup, isChannel: chat.isChannel) {
                    NotificationPrefs.quiet(content)
                }
            } else {
                content.body = preview
            }
            if fresh.count > 1 {
                content.subtitle = "Новых сообщений: \(fresh.count)"
            }
        } catch {
            AppLog.write("Notification extension sync failed: \(error.localizedDescription)")
        }
    }
}
