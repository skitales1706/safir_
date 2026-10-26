import Observation
import SwiftUI
import UIKit

/// Whole-app colour theme (Android AppThemes.kt). Classic follows Системная/Светлая/Тёмная, the
/// others fix one look.
struct ThemePalette: Identifiable {
    let id: Int
    let name: String
    let scheme: ColorScheme?
    let accent, accentDeep, background, backgroundMid, surface, card, pill, text, muted, separator, bubbleIn, metaIn: Color
    /// Concrete colours for the theme's preview card: background, header, incoming bubble, accent.
    let preview: [UInt32]

    private static func themed(_ id: Int, _ name: String, dark: Bool, bg: UInt32, mid: UInt32, surface: UInt32,
                               card: UInt32, hover: UInt32, accent: UInt32, accentDim: UInt32, text: UInt32,
                               muted: UInt32, bubbleIn: UInt32, metaIn: UInt32) -> ThemePalette {
        ThemePalette(id: id, name: name, scheme: dark ? .dark : .light,
                     accent: Color(hex: accent), accentDeep: Color(hex: accentDim), background: Color(hex: bg),
                     backgroundMid: Color(hex: mid), surface: Color(hex: surface), card: Color(hex: card),
                     pill: Color(hex: hover), text: Color(hex: text), muted: Color(hex: muted),
                     separator: Color(hex: hover), bubbleIn: Color(hex: bubbleIn), metaIn: Color(hex: metaIn),
                     preview: [bg, card, bubbleIn, accent])
    }

    static let all: [ThemePalette] = [
        ThemePalette(id: 0, name: "Классика", scheme: nil,
                     accent: Safir.dynamic(light: 0x0891A8, dark: 0x1ECFEF),
                     accentDeep: Safir.dynamic(light: 0x066B7D, dark: 0x0E7A90),
                     background: Safir.dynamic(light: 0xF4F7FA, dark: 0x050E1D),
                     backgroundMid: Safir.dynamic(light: 0xFFFFFF, dark: 0x091626),
                     surface: Safir.dynamic(light: 0xFFFFFF, dark: 0x0E1D32),
                     card: Safir.dynamic(light: 0xFFFFFF, dark: 0x112038),
                     pill: Safir.dynamic(light: 0xE9EFF5, dark: 0x112038),
                     text: Safir.dynamic(light: 0x0E1B2A, dark: 0xE8EEF7),
                     muted: Safir.dynamic(light: 0x5C7086, dark: 0x637B99),
                     separator: Safir.dynamic(light: 0xE3E9EF, dark: 0x16263D),
                     bubbleIn: Safir.dynamic(light: 0xFFFFFF, dark: 0x172A40),
                     metaIn: Safir.dynamic(light: 0x8A9BAD, dark: 0x7D93AE),
                     preview: [0xF4F7FA, 0xFFFFFF, 0xFFFFFF, 0x0891A8]),
        themed(1, "День", dark: false, bg: 0xF0F2F5, mid: 0xFFFFFF, surface: 0xFFFFFF, card: 0xFFFFFF, hover: 0xEEF1F5,
               accent: 0x3390EC, accentDim: 0x2A75C2, text: 0x0F1419, muted: 0x707579, bubbleIn: 0xFFFFFF, metaIn: 0x8E959B),
        themed(2, "Арктика", dark: false, bg: 0xDCE8F3, mid: 0xEEF4FA, surface: 0xF7FAFD, card: 0xFFFFFF, hover: 0xE6EEF7,
               accent: 0x3E88F7, accentDim: 0x2F6BC4, text: 0x0E1B2A, muted: 0x5E7389, bubbleIn: 0xFFFFFF, metaIn: 0x8A9BAD),
        themed(3, "Ночь", dark: true, bg: 0x0F0F10, mid: 0x161618, surface: 0x1C1C1E, card: 0x212123, hover: 0x2A2A2D,
               accent: 0x8774E1, accentDim: 0x5E4FB0, text: 0xF2F2F5, muted: 0x8A8A93, bubbleIn: 0x212123, metaIn: 0x8A8A93),
        themed(4, "Сумерки", dark: true, bg: 0x0E1621, mid: 0x17212B, surface: 0x1A2632, card: 0x1E2C3A, hover: 0x243445,
               accent: 0x5EB5F7, accentDim: 0x3A7FB5, text: 0xE9EEF4, muted: 0x7D8E9E, bubbleIn: 0x182533, metaIn: 0x7D8E9E),
        themed(5, "Лес", dark: true, bg: 0x0C1A14, mid: 0x10221A, surface: 0x132A20, card: 0x163126, hover: 0x1B3A2D,
               accent: 0x3DD68C, accentDim: 0x228A58, text: 0xE6F2EC, muted: 0x6F8F80, bubbleIn: 0x15301F, metaIn: 0x7FA090),
        themed(6, "AMOLED", dark: true, bg: 0x000000, mid: 0x000000, surface: 0x0A0A0A, card: 0x111111, hover: 0x1A1A1A,
               accent: 0x1ECFEF, accentDim: 0x0E7A90, text: 0xF0F0F0, muted: 0x7A7A7A, bubbleIn: 0x141414, metaIn: 0x7A7A7A),
    ]

    static func find(_ id: Int) -> ThemePalette { all.first { $0.id == id } ?? all[0] }
}

/// Colours of my own bubbles (Android BubbleStyles.kt): saturated in dark mode, pale tints in light.
struct BubbleStyle: Identifiable {
    let id: Int
    let name: String
    let top: Color
    let bottom: Color
    let meta: Color
    let swatch: [Color]

    private init(_ id: Int, _ name: String, dark: (UInt32, UInt32, UInt32), light: (UInt32, UInt32, UInt32)) {
        self.id = id
        self.name = name
        top = Safir.dynamic(light: light.0, dark: dark.0)
        bottom = Safir.dynamic(light: light.1, dark: dark.1)
        meta = Safir.dynamic(light: light.2, dark: dark.2)
        swatch = id == 0 ? [Color(hex: 0x1ECFEF), Color(hex: 0x0E7A90)] : [Color(hex: dark.0), Color(hex: dark.1)]
    }

    static let all: [BubbleStyle] = [
        BubbleStyle(0, "Бирюза", dark: (0x14566A, 0x0F4556, 0x8CCBD8), light: (0xD5F3F8, 0xC2ECF3, 0x4A8C9A)),
        BubbleStyle(1, "Синий", dark: (0x3A6EA5, 0x2B5278, 0xA9C8EC), light: (0xE3F0FF, 0xD1E6FF, 0x4C7FB5)),
        BubbleStyle(2, "Фиолет", dark: (0x7B4FD6, 0x5A36B0, 0xD2C1F7), light: (0xF0E8FF, 0xE5D8FF, 0x7A5BC2)),
        BubbleStyle(3, "Розовый", dark: (0xD64F8E, 0xA8336C, 0xF7C6DD), light: (0xFFE6F1, 0xFFD6E8, 0xB5507F)),
        BubbleStyle(4, "Зелёный", dark: (0x2E8B57, 0x1F6B43, 0xB0E6C8), light: (0xE3F8E9, 0xD2F2DC, 0x3F8A5C)),
        BubbleStyle(5, "Оранжевый", dark: (0xE07B39, 0xB85A22, 0xFFD6B8), light: (0xFFF0E2, 0xFFE3CC, 0xB06A35)),
        BubbleStyle(6, "Закат", dark: (0xE0567F, 0xE0833A, 0xFFDCC8), light: (0xFFE6EC, 0xFFEBD9, 0xB56050)),
        BubbleStyle(7, "Океан", dark: (0x2563EB, 0x0E8FB0, 0xC3E2FF), light: (0xE0EDFF, 0xDDF7FB, 0x3E7AA8)),
        BubbleStyle(8, "Красный", dark: (0xD9434E, 0xB02A36, 0xFFC2C7), light: (0xFFE5E7, 0xFFD6DA, 0xB5464F)),
        BubbleStyle(9, "Золото", dark: (0xC99A2E, 0xA67A16, 0xFFE7A8), light: (0xFFF6DA, 0xFFEDC0, 0xA07A22)),
        BubbleStyle(10, "Лотос", dark: (0x8E6FE0, 0xC06FD8, 0xEBD8FF), light: (0xF2EBFF, 0xF8E8FC, 0x8A63B5)),
        BubbleStyle(11, "Волна", dark: (0x1BA39C, 0x12807A, 0xB4F0EA), light: (0xDDF7F4, 0xCCF1ED, 0x2E8C84)),
        BubbleStyle(12, "Заря", dark: (0x6D4AD6, 0xE26D5A, 0xFFDCD2), light: (0xEEE6FF, 0xFFE6DE, 0x8E5C9C)),
        BubbleStyle(13, "Север", dark: (0x1E9E6A, 0x2B6FD6, 0xC8F0FF), light: (0xDFF7EC, 0xDCEBFF, 0x3D7F8A)),
        BubbleStyle(14, "Графит", dark: (0x4A5260, 0x363C47, 0xC5CBD6), light: (0xECEEF2, 0xE2E5EA, 0x6B7380)),
        BubbleStyle(15, "Полночь", dark: (0x2C3E8F, 0x1E2A66, 0xC3CDF7), light: (0xE3E8FF, 0xD6DDFB, 0x4F5DA8)),
        BubbleStyle(16, "Лайм", dark: (0x7FA81E, 0x5C8A10, 0xE4F5B8), light: (0xF1FAD6, 0xE6F5C0, 0x6D8A2A)),
        BubbleStyle(17, "Коралл", dark: (0xF06A5B, 0xD14A3E, 0xFFD0C9), light: (0xFFE9E5, 0xFFDCD5, 0xB5574C)),
        BubbleStyle(18, "Небесный", dark: (0x38A8E8, 0x1F86C8, 0xCDEBFF), light: (0xE2F4FF, 0xD3ECFF, 0x3D84B0)),
        BubbleStyle(19, "Рубин", dark: (0xB0204F, 0x85153A, 0xFFC4D6), light: (0xFFE3EC, 0xFFD3E0, 0xA8395F)),
        BubbleStyle(20, "Изумруд", dark: (0x0F9D76, 0x0A7A5B, 0xB8F2DF), light: (0xDCF7EE, 0xC9F0E3, 0x2E8A6C)),
        BubbleStyle(21, "Шоколад", dark: (0x8A5A3C, 0x6B4329, 0xF0D2BE), light: (0xF5E9E1, 0xEDDCCF, 0x8A5F45)),
        BubbleStyle(22, "Лаванда", dark: (0x9B8CE8, 0x7A6AD0, 0xE8E2FF), light: (0xF1EEFF, 0xE7E1FF, 0x7466B8)),
        BubbleStyle(23, "Персик", dark: (0xF2A07B, 0xE07F5C, 0xFFE2D4), light: (0xFFEFE6, 0xFFE3D6, 0xB87455)),
        BubbleStyle(24, "Неон", dark: (0xFF3CAC, 0x784BA0, 0xFFD1EC), light: (0xFFE3F3, 0xEDE3FF, 0xA04C8A)),
        BubbleStyle(25, "Море", dark: (0x00B4DB, 0x0083B0, 0xC7F1FF), light: (0xDDF6FF, 0xD0EEFA, 0x2C86A8)),
        BubbleStyle(26, "Роза", dark: (0xC98B95, 0xA8697A, 0xFFE5E5), light: (0xFCEDED, 0xF7E1E4, 0x9C6A72)),
        BubbleStyle(27, "Обсидиан", dark: (0x26262C, 0x141418, 0xB8B8C2), light: (0xE9E9EE, 0xDCDCE3, 0x5E5E6B)),
        BubbleStyle(28, "Солнце", dark: (0xF7A733, 0xF0602A, 0xFFE9C2), light: (0xFFF4D9, 0xFFE6D6, 0xB0702A)),
        BubbleStyle(29, "Аврора", dark: (0x2FB59A, 0x5B5BD6, 0xD6FFF6), light: (0xDDF8F2, 0xE3E3FF, 0x4A8A86)),
    ]

    static func style(_ id: Int) -> BubbleStyle { all.first { $0.id == id } ?? all[0] }
}

/// The doodles of the classic Safir wallpaper, drawn with SF Symbols.
enum DoodlePack {
    case classic

    var symbols: [String] {
        ["heart", "star", "cloud", "paperplane", "music.note", "bubble.left", "cat", "cup.and.saucer", "camera.macro", "moon"]
    }
}

/// Picture chat themes (Android ChatThemeImages.kt): thems/*.png -> scripts/gen_chat_themes.py ->
/// wp_<key>.webp + wp_<key>_thumb.webp, bundled straight from the Android res folder (project.yml).
struct ImageChatTheme: Identifiable, Equatable {
    let key: String
    let name: String

    var id: String { key }

    static let all: [ImageChatTheme] = [
        ImageChatTheme(key: "tj_ornament", name: "Таджикский орнамент"),
        ImageChatTheme(key: "mountains", name: "Горы Таджикистана"),
        ImageChatTheme(key: "tulips", name: "Тюльпаны"),
        ImageChatTheme(key: "heritage", name: "Наследие"),
        ImageChatTheme(key: "night_heritage", name: "Ночное наследие"),
        ImageChatTheme(key: "eastern_legends", name: "Легенды Востока"),
        ImageChatTheme(key: "neon_relics", name: "Древние символы"),
        ImageChatTheme(key: "cosmos_lilac", name: "Лиловый космос"),
        ImageChatTheme(key: "planets", name: "Планеты"),
        ImageChatTheme(key: "neon_forest", name: "Неоновый лес"),
        ImageChatTheme(key: "kaleidoscope", name: "Калейдоскоп"),
        ImageChatTheme(key: "neon_winter", name: "Зима"),
        ImageChatTheme(key: "neon_music", name: "Неоновая музыка"),
        ImageChatTheme(key: "game_over", name: "Game Over"),
        ImageChatTheme(key: "game_lineart", name: "Игры"),
        ImageChatTheme(key: "stickers", name: "Стикеры"),
        ImageChatTheme(key: "tech_doodles", name: "Технодудлы"),
        ImageChatTheme(key: "animals", name: "Животные"),
        ImageChatTheme(key: "romance", name: "Романтика"),
        ImageChatTheme(key: "math_board", name: "Математика"),
        ImageChatTheme(key: "school_board", name: "Школьная доска"),
    ]

    static func find(_ key: String) -> ImageChatTheme? { all.first { $0.key == key } }
}

/// A picked picture with WhatsApp's dimming (0...0.7) and Telegram's blur. Stored as
/// "theme:<key>?dim=<0-70>&blur=<0|1>" - the same string Android keeps.
struct ImageThemeSpec: Equatable {
    static let prefix = "theme:"
    static let maxDim = 0.7

    let theme: ImageChatTheme
    var dim: Double = 0
    var blur = false

    var raw: String { "\(Self.prefix)\(theme.key)?dim=\(Int((dim * 100).rounded()))&blur=\(blur ? 1 : 0)" }

    init(theme: ImageChatTheme, dim: Double = 0, blur: Bool = false) {
        self.theme = theme
        self.dim = dim
        self.blur = blur
    }

    /// nil for anything that is not a picture theme, or one that no longer exists.
    init?(raw: String) {
        guard raw.hasPrefix(Self.prefix) else { return nil }
        let parts = raw.dropFirst(Self.prefix.count).split(separator: "?", maxSplits: 1)
        guard let key = parts.first, let theme = ImageChatTheme.find(String(key)) else { return nil }
        var params: [Substring: Substring] = [:]
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { params[kv[0]] = kv[1] }
            }
        }
        let dim = min(max(params["dim"].flatMap { Int($0) } ?? 0, 0), 70)
        self.init(theme: theme, dim: Double(dim) / 100, blur: params["blur"] == "1")
    }
}

/// What is behind the messages. Stored as "" (classic), "none", "theme:<key>?..." or
/// "photo:<time>". The old drawn "builtin:<id>" wallpapers are gone - a saved one shows classic.
enum WallpaperChoice: Equatable {
    case classic, none, image(ImageThemeSpec), photo

    init(_ raw: String) {
        if raw == "none" {
            self = .none
        } else if let spec = ImageThemeSpec(raw: raw) {
            self = .image(spec)
        } else if raw.hasPrefix("photo:") {
            self = .photo
        } else {
            self = .classic
        }
    }

    var imageKey: String? {
        if case .image(let spec) = self { return spec.theme.key }
        return nil
    }
}

/// Telegram's "theme with wallpaper" (Android ThemeWallpaperPresets.kt): one tap sets the colour
/// theme, the bubble colour and one of the pictures. One preset per picture; the pictures are all
/// dark, so every preset uses a dark theme: 3 Ночь, 4 Сумерки, 5 Лес, 6 AMOLED.
struct ThemePreset: Identifiable, Equatable {
    let emoji: String
    let imageKey: String
    let theme: Int
    let bubble: Int

    var id: String { imageKey }
    var image: ImageChatTheme { ImageChatTheme.find(imageKey) ?? ImageChatTheme.all[0] }
    var name: String { image.name }

    static let all: [ThemePreset] = [
        ThemePreset(emoji: "🇹🇯", imageKey: "tj_ornament", theme: 4, bubble: 0),
        ThemePreset(emoji: "⛰️", imageKey: "mountains", theme: 4, bubble: 7),
        ThemePreset(emoji: "🌷", imageKey: "tulips", theme: 3, bubble: 3),
        ThemePreset(emoji: "🏺", imageKey: "heritage", theme: 6, bubble: 9),
        ThemePreset(emoji: "🌙", imageKey: "night_heritage", theme: 4, bubble: 12),
        ThemePreset(emoji: "🐉", imageKey: "eastern_legends", theme: 3, bubble: 10),
        ThemePreset(emoji: "🗿", imageKey: "neon_relics", theme: 6, bubble: 0),
        ThemePreset(emoji: "🔮", imageKey: "cosmos_lilac", theme: 3, bubble: 2),
        ThemePreset(emoji: "🪐", imageKey: "planets", theme: 4, bubble: 15),
        ThemePreset(emoji: "🌲", imageKey: "neon_forest", theme: 5, bubble: 4),
        ThemePreset(emoji: "🍄", imageKey: "kaleidoscope", theme: 5, bubble: 11),
        ThemePreset(emoji: "⛄", imageKey: "neon_winter", theme: 4, bubble: 1),
        ThemePreset(emoji: "🎵", imageKey: "neon_music", theme: 3, bubble: 10),
        ThemePreset(emoji: "🎮", imageKey: "game_over", theme: 6, bubble: 8),
        ThemePreset(emoji: "🕹️", imageKey: "game_lineart", theme: 4, bubble: 2),
        ThemePreset(emoji: "🤩", imageKey: "stickers", theme: 3, bubble: 3),
        ThemePreset(emoji: "💻", imageKey: "tech_doodles", theme: 6, bubble: 0),
        ThemePreset(emoji: "🐾", imageKey: "animals", theme: 5, bubble: 9),
        ThemePreset(emoji: "💕", imageKey: "romance", theme: 3, bubble: 3),
        ThemePreset(emoji: "➗", imageKey: "math_board", theme: 5, bubble: 4),
        ThemePreset(emoji: "👨‍🏫", imageKey: "school_board", theme: 5, bubble: 13),
    ]
}

/// The look currently in use. Not tied to the main actor: Safir's colours read it from anywhere,
/// and every view that draws with them redraws when it changes (Observation).
@Observable
final class ThemeRuntime {
    static let shared = ThemeRuntime()

    var themeId: Int {
        didSet { UserDefaults.standard.set(themeId, forKey: "safir.colorTheme") }
    }
    var bubbleId: Int {
        didSet { UserDefaults.standard.set(bubbleId, forKey: "safir.bubbleStyle") }
    }
    var wallpaper: String {
        didSet { UserDefaults.standard.set(wallpaper, forKey: "safir.wallpaper") }
    }

    @ObservationIgnored private var photo: (key: String, image: UIImage)?

    private init() {
        let defaults = UserDefaults.standard
        themeId = defaults.integer(forKey: "safir.colorTheme")
        bubbleId = defaults.integer(forKey: "safir.bubbleStyle")
        wallpaper = defaults.string(forKey: "safir.wallpaper") ?? ""
    }

    var palette: ThemePalette { ThemePalette.find(themeId) }
    var bubble: BubbleStyle { BubbleStyle.style(bubbleId) }

    static var photoURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("wallpaper.jpg")
    }

    /// My own wallpaper photo, read once per pick.
    func photoImage() -> UIImage? {
        let key = wallpaper
        if let photo, photo.key == key { return photo.image }
        guard let image = UIImage(contentsOfFile: Self.photoURL.path) else { return nil }
        photo = (key, image)
        return image
    }

    /// Saves a picked photo (cut to at most 1600 px) and makes it the wallpaper.
    func setPhoto(_ image: UIImage) {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let url = Self.photoURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        wallpaper = "photo:\(Int(Date().timeIntervalSince1970))"
    }
}
