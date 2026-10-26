import Network
import Observation
import SwiftUI
import UIKit

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Settings → Данные и память → Автозагрузка медиа: photos and videos by network, like Telegram.
/// Off means the bubble shows its blurred preview with a download button instead.
@MainActor
@Observable
final class MediaAutoload {
    static let shared = MediaAutoload()

    private(set) var onCellular = false
    var photosCellular: Bool { didSet { save() } }
    var videosCellular: Bool { didSet { save() } }
    var photosWifi: Bool { didSet { save() } }
    var videosWifi: Bool { didSet { save() } }

    private let monitor = NWPathMonitor()

    private init() {
        let d = UserDefaults.standard
        photosCellular = d.object(forKey: "autoload_photos_cell") as? Bool ?? true
        videosCellular = d.object(forKey: "autoload_videos_cell") as? Bool ?? false
        photosWifi = d.object(forKey: "autoload_photos_wifi") as? Bool ?? true
        videosWifi = d.object(forKey: "autoload_videos_wifi") as? Bool ?? true
        monitor.pathUpdateHandler = { path in
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
            Task { @MainActor in MediaAutoload.shared.onCellular = cellular }
        }
        monitor.start(queue: DispatchQueue(label: "safir.autoload"))
    }

    /// May this incoming photo/video download by itself right now?
    func allows(_ type: String) -> Bool {
        switch type {
        case "image": return onCellular ? photosCellular : photosWifi
        case "video": return onCellular ? videosCellular : videosWifi
        default: return true
        }
    }

    /// Already on this phone (sent from here, or downloaded before).
    static func isLocal(_ m: MessageItem) -> Bool {
        if let path = m.localPath, FileManager.default.fileExists(atPath: path) { return true }
        return FileManager.default.fileExists(atPath: MediaCache.file(messageId: m.serverId, ext: MediaCache.ext(for: m.type)).path)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(photosCellular, forKey: "autoload_photos_cell")
        d.set(videosCellular, forKey: "autoload_videos_cell")
        d.set(photosWifi, forKey: "autoload_photos_wifi")
        d.set(videosWifi, forKey: "autoload_videos_wifi")
    }
}

/// Look-and-feel switches stored on this phone (Android SessionManager prefs).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let fontRange: ClosedRange<Double> = 13...23

    private let defaults = UserDefaults.standard

    var theme: ThemeMode {
        didSet { defaults.set(theme.rawValue, forKey: "safir.theme") }
    }
    /// Message text size in points.
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "safir.fontSize") }
    }
    var bubbleStyle: Int {
        get { ThemeRuntime.shared.bubbleId }
        set { ThemeRuntime.shared.bubbleId = newValue }
    }
    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Safir.hapticsKey) }
    }
    var notifPreview: Bool {
        didSet { NotificationPrefs.preview = notifPreview }
    }
    var notifSound: Bool {
        didSet { NotificationPrefs.sound = notifSound }
    }
    var notifInApp: Bool {
        didSet { NotificationPrefs.inApp = notifInApp }
    }
    var notifPrivate: Bool {
        didSet { NotificationPrefs.privateChats = notifPrivate }
    }
    var notifGroups: Bool {
        didSet { NotificationPrefs.groups = notifGroups }
    }
    var notifChannels: Bool {
        didSet { NotificationPrefs.channels = notifChannels }
    }
    /// Telegram's power saving: no decorative animations (also while iOS Low Power Mode is on).
    var powerSaving: Bool {
        didSet { defaults.set(powerSaving, forKey: "safir.powerSaving") }
    }

    var reduceAnimations: Bool { powerSaving || ProcessInfo.processInfo.isLowPowerModeEnabled }

    private init() {
        theme = ThemeMode(rawValue: defaults.string(forKey: "safir.theme") ?? "") ?? .system
        let size = defaults.double(forKey: "safir.fontSize")
        fontSize = size == 0 ? 17 : size
        haptics = defaults.object(forKey: Safir.hapticsKey) as? Bool ?? true
        notifPreview = NotificationPrefs.preview
        notifSound = NotificationPrefs.sound
        notifInApp = NotificationPrefs.inApp
        notifPrivate = NotificationPrefs.privateChats
        notifGroups = NotificationPrefs.groups
        notifChannels = NotificationPrefs.channels
        powerSaving = defaults.bool(forKey: "safir.powerSaving")
    }

    var bubble: BubbleStyle { ThemeRuntime.shared.bubble }

    /// What the window shows: a fixed theme's own look, else Системная/Светлая/Тёмная.
    var effectiveScheme: ColorScheme? { ThemeRuntime.shared.palette.scheme ?? theme.scheme }

    var effectiveStyle: UIUserInterfaceStyle {
        switch effectiveScheme {
        case .light: return .light
        case .dark: return .dark
        default: return .unspecified
        }
    }

    func resetNotifications() {
        notifPreview = true
        notifSound = true
        notifInApp = true
        notifPrivate = true
        notifGroups = true
        notifChannels = true
    }
}

/// Telegram's theme switch: the new look spreads from the tapped point in a growing circle over
/// a snapshot of the old one.
@MainActor
enum ThemeSwitcher {
    static func apply(_ mode: ThemeMode, from point: CGPoint?) {
        guard mode != AppSettings.shared.theme else { return }
        transition(from: point) { AppSettings.shared.theme = mode }
    }

    /// A colour theme, or a whole "theme with wallpaper" preset.
    static func apply(theme: Int, bubble: Int? = nil, wallpaper: String? = nil, from point: CGPoint?) {
        let runtime = ThemeRuntime.shared
        transition(from: point) {
            runtime.themeId = theme
            if let bubble { runtime.bubbleId = bubble }
            if let wallpaper { runtime.wallpaper = wallpaper }
        }
    }

    /// A whole theme picked in the full-screen preview: that preview already showed the new look,
    /// so no circle - just switch while it slides away.
    static func applyNow(theme: Int, bubble: Int, wallpaper: String) {
        let runtime = ThemeRuntime.shared
        withAnimation(Safir.spring) {
            runtime.themeId = theme
            runtime.bubbleId = bubble
            runtime.wallpaper = wallpaper
        }
        keyWindow?.overrideUserInterfaceStyle = AppSettings.shared.effectiveStyle
    }

    /// Runs `change` under a snapshot of the old look and reveals the new one in a growing circle.
    static func transition(from point: CGPoint?, _ change: () -> Void) {
        guard !AppSettings.shared.reduceAnimations, let window = keyWindow,
              let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            change()
            keyWindow?.overrideUserInterfaceStyle = AppSettings.shared.effectiveStyle
            return
        }
        window.addSubview(snapshot)
        change()
        window.overrideUserInterfaceStyle = AppSettings.shared.effectiveStyle

        let bounds = window.bounds
        let center = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = hypot(max(center.x, bounds.width - center.x), max(center.y, bounds.height - center.y))
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        let start = holePath(bounds, center, 0)
        let end = holePath(bounds, center, radius)
        mask.path = start
        snapshot.layer.mask = mask

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = start
        animation.toValue = end
        animation.duration = 0.55
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        CATransaction.begin()
        CATransaction.setCompletionBlock { snapshot.removeFromSuperview() }
        mask.path = end
        mask.add(animation, forKey: "reveal")
        CATransaction.commit()
    }

    /// Launch: the window follows the stored choice before the first frame.
    static func applyStored() {
        keyWindow?.overrideUserInterfaceStyle = AppSettings.shared.effectiveStyle
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }

    private static func holePath(_ rect: CGRect, _ center: CGPoint, _ radius: CGFloat) -> CGPath {
        let path = UIBezierPath(rect: rect)
        path.append(UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true))
        return path.cgPath
    }
}
