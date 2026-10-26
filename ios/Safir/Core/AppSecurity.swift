import LocalAuthentication
import Observation
import SwiftUI

/// Organisation DLP policy (backend dlp_policy.py, GET /policies/client) and the app lock.
/// iOS cannot block screenshots outright; with block_screenshots the app hides its content in
/// the app switcher and while the screen is being recorded or mirrored.
struct DLPPolicy: Decodable, Equatable {
    var blockForwarding = false
    var blockCopy = false
    var blockScreenshots = false
    var blockMediaSave = false
    var watermark = false
    var allowedMedia: [String] = ["image", "video", "audio", "file"]
    var maxFileMb = 0
    var wipe = false
    /// Antivirus check of every file before sending (AvScan.swift).
    var scanFiles = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockForwarding = try c.decodeIfPresent(Bool.self, forKey: .blockForwarding) ?? false
        blockCopy = try c.decodeIfPresent(Bool.self, forKey: .blockCopy) ?? false
        blockScreenshots = try c.decodeIfPresent(Bool.self, forKey: .blockScreenshots) ?? false
        blockMediaSave = try c.decodeIfPresent(Bool.self, forKey: .blockMediaSave) ?? false
        watermark = try c.decodeIfPresent(Bool.self, forKey: .watermark) ?? false
        allowedMedia = try c.decodeIfPresent([String].self, forKey: .allowedMedia) ?? allowedMedia
        maxFileMb = try c.decodeIfPresent(Int.self, forKey: .maxFileMb) ?? 0
        wipe = try c.decodeIfPresent(Bool.self, forKey: .wipe) ?? false
        scanFiles = try c.decodeIfPresent(Bool.self, forKey: .scanFiles) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case blockForwarding, blockCopy, blockScreenshots, blockMediaSave, watermark, allowedMedia, maxFileMb, wipe, scanFiles
    }

    /// Nil when allowed, else the reason to show.
    func refusal(type: String, bytes: Int) -> String? {
        if !allowedMedia.contains(type) { return "Организация запретила отправку этого типа файлов" }
        if maxFileMb > 0 && bytes > maxFileMb * 1024 * 1024 { return "Файл больше \(maxFileMb) МБ" }
        return nil
    }
}

@MainActor
@Observable
final class AppSecurity {
    static let shared = AppSecurity()

    private var serverPolicy = DLPPolicy()
    /// The server's policy, tightened by the MDM (Mdm.swift).
    var policy: DLPPolicy { Mdm.shared.tighten(serverPolicy) }
    private(set) var locked = false
    private(set) var screenCaptured = false
    var lockEnabled: Bool {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: "app_lock") }
    }

    private init() {
        lockEnabled = UserDefaults.standard.bool(forKey: "app_lock")
        locked = UserDefaults.standard.bool(forKey: "app_lock") || Passcode.shared.isOn
        screenCaptured = UIScreen.main.isCaptured
        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppSecurity.shared.screenCaptured = UIScreen.main.isCaptured }
        }
    }

    /// Content must be hidden right now (recording/mirroring under a screenshot ban).
    var hideContent: Bool { policy.blockScreenshots && screenCaptured }

    func refreshPolicy() async {
        let session = Session.shared
        guard case .loggedIn = session.state else { return }
        do {
            let p = try await session.api.get("policies/client", query: ["device_id": session.deviceId], as: DLPPolicy.self)
            serverPolicy = p
            if p.wipe {
                let token = session.api.token
                let id = session.deviceId
                session.forceSignOut(reason: "remote wipe", wipe: true)
                _ = try? await session.api.send("POST", "devices/\(id)/wiped", body: nil, bearer: token)
            }
        } catch {
            AppLog.write("Policy refresh failed: \(error.localizedDescription)")
        }
    }

    private var backgroundedAt: Date?

    func appWentToBackground() {
        backgroundedAt = Date()
        let passcode = Passcode.shared
        if passcode.isOn ? passcode.autoLockMinutes == 0 : lockEnabled { locked = true }
    }

    /// Back from the background: the passcode is asked once its auto-lock delay has passed.
    func appBecameActive() {
        let passcode = Passcode.shared
        guard passcode.isOn, !locked, let since = backgroundedAt else { return }
        if Date().timeIntervalSince(since) >= Double(passcode.autoLockMinutes * 60) { locked = true }
    }

    /// The passcode screen accepted the code (or Face ID).
    func unlockedByPasscode() {
        locked = false
        backgroundedAt = nil
    }

    func unlock() async {
        // With a passcode only Face ID / Touch ID may skip the code screen.
        if Passcode.shared.isOn {
            if await Passcode.shared.biometricUnlock() { unlockedByPasscode() }
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on the phone at all - nothing to check against.
            locked = false
            return
        }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Открыть Safir")) == true {
            locked = false
        }
    }
}

/// Covers the app while locked, and in the app switcher when screenshots are banned.
struct PrivacyCover: View {
    let showUnlock: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44))
                Text("Safir").font(.title2.bold())
                if showUnlock {
                    Button("Разблокировать") { Task { await AppSecurity.shared.unlock() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// The signed-in user's name across the chat when the organisation asks for a watermark - a
/// photo of the screen then shows who leaked it.
struct WatermarkOverlay: View {
    let text: String

    var body: some View {
        GeometryReader { geo in
            let rows = Int(geo.size.height / 90) + 1
            VStack(spacing: 60) {
                ForEach(0..<rows, id: \.self) { _ in
                    Text(text).font(.footnote.bold()).foregroundStyle(Color.primary.opacity(0.08))
                        .rotationEffect(.degrees(-30)).frame(maxWidth: .infinity)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
