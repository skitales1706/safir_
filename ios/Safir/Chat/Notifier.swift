import Foundation
import UserNotifications

/// Local banners while the app is open but another chat is on screen. In the background the
/// Notification Service Extension shows them instead (it decrypts the APNs wake-up itself).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Set by the UI - tapping a banner opens that chat.
    var openChat: ((String) -> Void)?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func incoming(chat: ChatItem, senderName: String?, preview: String) {
        guard !chat.isMuted, !NotificationPrefs.mutedNow(chat.id), NotificationPrefs.inApp,
              NotificationPrefs.enabled(isGroup: chat.isGroup, isChannel: chat.isChannel) else { return }
        let content = UNMutableNotificationContent()
        content.title = chat.name
        content.body = senderName.map { "\($0): \(preview)" } ?? preview
        content.sound = .default
        content.threadIdentifier = chat.id
        content.userInfo = ["chat_id": chat.id]
        NotificationPrefs.apply(to: content)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// The chat was opened: its delivered banners go away.
    func clear(chatId: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notes in
            let ids = notes.filter { $0.request.content.threadIdentifier == chatId }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let chatId = info["chat_id"] as? String
        // A banner of another signed-in account (NotificationService): switch to it first.
        let account = info["account_id"] as? String
        Task { @MainActor in
            if let account, account != Accounts.shared.activeId {
                await Accounts.shared.switchTo(account)
            } else if let chatId {
                Notifier.shared.openChat?(chatId)
            }
            completionHandler()
        }
    }
}
