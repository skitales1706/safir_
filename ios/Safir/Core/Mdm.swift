import Foundation
import Observation

/// Values IT pushes through the MDM - the same keys as Android's res/xml/app_restrictions.xml
/// (DEPLOYMENT.md §19). Empty = not managed.
struct ManagedConfig: Equatable {
    var serverUrl = ""
    var requireSso = false
    var disableRegistration = false
    var blockScreenshots = false
    var blockCopy = false
    var blockMediaSave = false
    var blockForwarding = false
    var orgCaPem = ""
    var serverPins: [String] = []

    init() {}

    init(_ d: [String: Any]) {
        func string(_ key: String) -> String { (d[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        func bool(_ key: String) -> Bool {
            if let b = d[key] as? Bool { return b }
            if let n = d[key] as? NSNumber { return n.boolValue }
            if let s = d[key] as? String { return s == "true" || s == "1" }
            return false
        }
        serverUrl = string("server_url")
        requireSso = bool("require_sso")
        disableRegistration = bool("disable_registration")
        blockScreenshots = bool("block_screenshots")
        blockCopy = bool("block_copy")
        blockMediaSave = bool("block_media_save")
        blockForwarding = bool("block_forwarding")
        orgCaPem = string("org_ca_pem")
        serverPins = string("server_pins")
            .components(separatedBy: CharacterSet(charactersIn: ", \n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("sha256/") }
    }
}

/// Managed app configuration (Intune, Workspace ONE, Jamf...): on an iPhone enrolled in the
/// organisation's MDM, IT sets the server address, "SSO only" and DLP switches - the iOS twin of
/// Android's Mdm.kt. The MDM switches only make the server's DLP policy stricter, never looser.
/// The CA and pins go to the shared Keychain so PinnedTrust in the push extension sees them too.
@MainActor
@Observable
final class Mdm {
    static let shared = Mdm()
    private static let managedKey = "com.apple.configuration.managed"

    private(set) var config = ManagedConfig()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        read()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Mdm.shared.read() }
        }
    }

    private func read() {
        let next = ManagedConfig(UserDefaults.standard.dictionary(forKey: Self.managedKey) ?? [:])
        guard next != config else { return }
        config = next
        if next.serverUrl.hasPrefix("https://") {
            let url = next.serverUrl.hasSuffix("/") ? next.serverUrl : next.serverUrl + "/"
            if Keychain.get("base_url") != url, let parsed = URL(string: url) {
                Keychain.set(url, for: "base_url")
                APIClient.shared.baseURL = parsed
                AppLog.write("MDM: server set to \(url)")
            }
        } else if !next.serverUrl.isEmpty {
            AppLog.write("MDM: ignoring server_url without https://")
        }
        Keychain.set(next.orgCaPem.isEmpty ? nil : next.orgCaPem, for: "org_ca_pem")
        Keychain.set(next.serverPins.isEmpty ? nil : next.serverPins.joined(separator: ","), for: "server_pins")
    }

    /// The server's DLP policy, made stricter by whatever the MDM forces.
    func tighten(_ p: DLPPolicy) -> DLPPolicy {
        var p = p
        p.blockScreenshots = p.blockScreenshots || config.blockScreenshots
        p.blockCopy = p.blockCopy || config.blockCopy
        p.blockMediaSave = p.blockMediaSave || config.blockMediaSave
        p.blockForwarding = p.blockForwarding || config.blockForwarding
        return p
    }
}
