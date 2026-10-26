import Foundation
import MachO

/// Best-effort jailbreak detection, the iOS twin of Android's RootCheck.kt. Reported at device
/// registration (is_rooted), where the organisation's device policy may refuse the device
/// (backend device_policy.py -> 403 device_not_allowed). A determined user can hide a jailbreak;
/// this catches the common rootful/rootless ones (checkra1n, unc0ver, palera1n, Dopamine).
enum JailbreakCheck {
    static let isJailbroken: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return suspiciousPaths() || canWriteOutsideSandbox() || injectedLibraries()
        #endif
    }()

    private static func suspiciousPaths() -> Bool {
        let paths = [
            "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib", "/usr/lib/TweakInject",
            "/bin/bash", "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt/",
            "/var/jb", "/var/binpack", "/private/preboot/jb",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/safir_jb_probe.txt"
        do {
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private static func injectedLibraries() -> Bool {
        if ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] != nil { return true }
        let markers = ["mobilesubstrate", "substitute", "tweakinject", "libhooker", "ellekit", "frida", "cycript"]
        for i in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(i) else { continue }
            let image = String(cString: name).lowercased()
            if markers.contains(where: { image.contains($0) }) { return true }
        }
        return false
    }
}
