import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// Telegram-style in-app passcode (Android AppLock + PasscodeSetupActivity): 4 digits, an
/// auto-lock delay and optional Face ID / Touch ID. Only a salted hash is kept, in the Keychain.
@MainActor
@Observable
final class Passcode {
    static let shared = Passcode()
    /// Minutes in the background before the code is asked again (0 = at once).
    static let autoLockOptions = [0, 1, 5, 60, 300]
    static let length = 4
    private static let maxAttempts = 5

    private(set) var isOn: Bool
    var autoLockMinutes: Int {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: "passcode_autolock") }
    }
    var biometrics: Bool {
        didSet { UserDefaults.standard.set(biometrics, forKey: "passcode_biometrics") }
    }
    /// After too many wrong codes the pad is frozen until then.
    private(set) var lockedUntil: Date?
    private var failed = 0

    private init() {
        let defaults = UserDefaults.standard
        // The Keychain outlives a reinstall but UserDefaults do not: a fresh install drops an old
        // code, so "forgot the code - reinstall" really works.
        if !defaults.bool(forKey: "passcode_install_seen") {
            Keychain.set(nil, for: "passcode_hash")
            Keychain.set(nil, for: "passcode_salt")
            defaults.set(true, forKey: "passcode_install_seen")
        }
        isOn = Keychain.get("passcode_hash") != nil
        autoLockMinutes = defaults.object(forKey: "passcode_autolock") as? Int ?? 1
        biometrics = defaults.object(forKey: "passcode_biometrics") as? Bool ?? true
    }

    func set(_ code: String) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        Keychain.set(salt, for: "passcode_salt")
        Keychain.set(Self.hash(code, salt: salt), for: "passcode_hash")
        isOn = true
        failed = 0
        lockedUntil = nil
    }

    func disable() {
        Keychain.set(nil, for: "passcode_hash")
        Keychain.set(nil, for: "passcode_salt")
        isOn = false
    }

    /// True for the right code. Five wrong ones in a row freeze the pad, longer each time.
    func check(_ code: String) -> Bool {
        if let until = lockedUntil, until > Date() { return false }
        guard let salt = Keychain.get("passcode_salt"), let stored = Keychain.get("passcode_hash") else { return false }
        if Self.hash(code, salt: salt) == stored {
            failed = 0
            lockedUntil = nil
            return true
        }
        failed += 1
        if failed % Self.maxAttempts == 0 {
            lockedUntil = Date().addingTimeInterval(Double(30 * (failed / Self.maxAttempts)))
        }
        return false
    }

    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return nil
        }
    }

    func biometricUnlock() async -> Bool {
        guard isOn, biometrics, biometryName != nil else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = "Ввести код"
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                   localizedReason: "Открыть Safir")) == true
    }

    static func label(_ minutes: Int) -> String {
        switch minutes {
        case 0: return tr("Сразу")
        case 1..<60: return tr("Через %d мин", minutes)
        default: return tr("Через %d ч", minutes / 60)
        }
    }

    private static func hash(_ code: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + ":" + code).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
