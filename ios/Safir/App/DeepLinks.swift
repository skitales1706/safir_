import SwiftUI
import UIKit

/// safir:// links (widgets, contact cards) and the home-screen quick actions (long press on the
/// app icon: new message, Избранное, search).
extension TabRouter {
    /// safir://services/weather|rates, safir://contact/<user id>, safir://chats/new|saved|search.
    @MainActor
    func open(_ url: URL) {
        guard url.scheme == "safir" else { return }
        let path = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "services":
            chatPath = []
            tab = .services
        case "contact":
            guard let id = path.first?.lowercased(), UUID(uuidString: id) != nil else { return }
            Task { @MainActor in
                let me = ChatService.shared.myUserId
                guard id != me.lowercased() else { return }
                if let user = ChatStore.shared.user(id) {
                    openChat(with: user)
                } else if let user = try? await Session.shared.api.get("users/\(id)", as: APIUser.self) {
                    ChatStore.shared.upsert(users: [user])
                    openChat(with: user)
                }
            }
        case "chats":
            chatPath = []
            tab = .chats
            pendingAction = path.first
        default:
            break
        }
    }

    /// UIApplicationShortcutItem.type -> link.
    @MainActor
    func perform(shortcut type: String) {
        switch type {
        case "tj.safir.new-chat": open(URL(string: "safir://chats/new")!)
        case "tj.safir.saved": open(URL(string: "safir://chats/saved")!)
        case "tj.safir.search": open(URL(string: "safir://chats/search")!)
        default: break
        }
    }

    /// The icon's quick actions, set on every launch so they follow the app's language.
    @MainActor
    static func installShortcuts() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(type: "tj.safir.new-chat", localizedTitle: tr("Новое сообщение"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil")),
            UIApplicationShortcutItem(type: "tj.safir.saved", localizedTitle: tr("Избранное"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "bookmark")),
            UIApplicationShortcutItem(type: "tj.safir.search", localizedTitle: tr("Поиск"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass")),
        ]
    }
}

/// SwiftUI apps get quick actions through a scene delegate: at launch (connectionOptions) and
/// while running (performActionFor).
final class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let type = connectionOptions.shortcutItem?.type else { return }
        Task { @MainActor in
            // Let the UI and the session come up first.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            TabRouter.shared.perform(shortcut: type)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            TabRouter.shared.perform(shortcut: shortcutItem.type)
            completionHandler(true)
        }
    }
}

extension AppDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShortcutSceneDelegate.self
        return config
    }
}
