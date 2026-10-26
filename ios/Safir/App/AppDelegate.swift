import UIKit
import UserNotifications

/// APNs registration (backend/apns.py). The token is handed to the server only once this install
/// is a registered device with Signal keys - a push for a device that can't decrypt is useless.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// A VoIP push can launch the app in the background with no UI - PushKit must be listening
    /// before launch finishes, or iOS kills the app for not reporting the call.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Keychain.get("auth_token") != nil {
            MainActor.assumeIsolated { CallService.shared.registerVoIP() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in Session.shared.pushTokenReceived(hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLog.write("APNs registration failed: \(error.localizedDescription)")
    }
}

enum PushRegistrar {
    @MainActor
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        AppLog.write("Notifications permission: \(granted ? "granted" : "denied")")
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
