import Foundation
import Security

/// Session secrets (auth token, device id, Signal identity). Shared with the Notification
/// Service Extension through a Keychain access group, and AfterFirstUnlock - not WhenUnlocked -
/// because that extension has to read them while the phone is locked.
enum Keychain {
    private static let service = "tj.safir.messenger"

    /// "<TeamID>.tj.safir.shared" from Info.plist (SafirKeychainGroup). Unsigned simulator builds
    /// have no entitlement for it - then the item lives in the app's default group.
    private static let accessGroup: String? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SafirKeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$(") else { return nil }
        return group
    }()

    private static func baseQuery(_ key: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    static func set(_ value: String?, for key: String) {
        if write(value, for: key, group: accessGroup) == errSecMissingEntitlement {
            _ = write(value, for: key, group: nil)
        }
    }

    private static func write(_ value: String?, for key: String, group: String?) -> OSStatus {
        let base = baseQuery(key, group: group)
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return errSecSuccess }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess && status != errSecMissingEntitlement {
            AppLog.write("Keychain write failed for \(key): \(status)")
        }
        return status
    }

    static func get(_ key: String) -> String? {
        if let value = read(key, group: accessGroup) { return value }
        return accessGroup == nil ? nil : read(key, group: nil)
    }

    private static func read(_ key: String, group: String?) -> String? {
        var query = baseQuery(key, group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
