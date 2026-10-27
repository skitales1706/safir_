import ImageIO
import SwiftUI
import UIKit

/// Safir's own sticker pack, drawn in code like Android's Stickers.kt (no image assets).
/// On the wire a sticker is an ordinary END-TO-END ENCRYPTED text message whose content is the
/// token `[sticker:<id>]` - the whole text path keeps working, an older client shows the token.
struct StickerDef: Identifiable {
    enum Motion { case beat, bounce, shake, float, wave, spin, pop, fly, tilt }

    let id: String
    let emoji: String
    var caption: String?
    var colors: [Color] = [Color(hex: 0x1ECFEF), Color(hex: 0x0E7A90)]
    var motion: Motion = .bounce
    var particle: String?
    /// Animated WebP in the bundle's spirit_stickers/ folder (the "Дух S" pack).
    var webp: String?

    static let pack: [StickerDef] = [
        StickerDef(id: "salom", emoji: "👋", caption: "Салом!", colors: [Color(hex: 0x22C55E), Color(hex: 0x15803D)], motion: .wave, particle: "✨"),
        StickerDef(id: "rahmat", emoji: "🙏", caption: "Раҳмат!", colors: [Color(hex: 0x8B5CF6), Color(hex: 0x6D28D9)], motion: .bounce, particle: "✨"),
        StickerDef(id: "ofarin", emoji: "👏", caption: "Офарин!", colors: [Color(hex: 0xF59E0B), Color(hex: 0xD97706)], motion: .shake, particle: "🎊"),
        StickerDef(id: "khush", emoji: "🌸", caption: "Хуш омадед!", colors: [Color(hex: 0xEC4899), Color(hex: 0xBE185D)], motion: .float, particle: "✨"),
        StickerDef(id: "choy", emoji: "🍵", caption: "Чой нӯшем?", colors: [Color(hex: 0x14B8A6), Color(hex: 0x0F766E)], motion: .tilt, particle: "💨"),
        StickerDef(id: "dust", emoji: "❤️", caption: "Туро дӯст медорам", colors: [Color(hex: 0xEF4444), Color(hex: 0xB91C1C)], motion: .beat, particle: "💕"),
        StickerDef(id: "tabrik", emoji: "🎉", caption: "Табрик!", colors: [Color(hex: 0xF97316), Color(hex: 0xEA580C)], motion: .pop, particle: "🎊"),
        StickerDef(id: "shab", emoji: "🌙", caption: "Шаби хуш", colors: [Color(hex: 0x6366F1), Color(hex: 0x3730A3)], motion: .float, particle: "💤"),
        StickerDef(id: "hahaha", emoji: "😂", caption: "Ха-ха-ха", colors: [Color(hex: 0xF59E0B), Color(hex: 0xB45309)], motion: .shake, particle: "💧"),
        StickerDef(id: "bale", emoji: "👍", caption: "Бале!", colors: [Color(hex: 0x3B82F6), Color(hex: 0x1D4ED8)], motion: .pop, particle: "✨"),
        StickerDef(id: "intizor", emoji: "⏳", caption: "Интизор шав", colors: [Color(hex: 0x64748B), Color(hex: 0x334155)], motion: .spin),
        StickerDef(id: "vatan", emoji: "🇹🇯", caption: "Ватан", colors: [Color(hex: 0xEF4444), Color(hex: 0x16A34A)], motion: .wave, particle: "✨"),
        StickerDef(id: "heart", emoji: "❤️", motion: .beat, particle: "💕"),
        StickerDef(id: "fire", emoji: "🔥", motion: .shake, particle: "🔥"),
        StickerDef(id: "love", emoji: "😍", motion: .float, particle: "💕"),
        StickerDef(id: "cry", emoji: "😭", motion: .shake, particle: "💧"),
        StickerDef(id: "cool", emoji: "😎", motion: .bounce, particle: "✨"),
        StickerDef(id: "party", emoji: "🥳", motion: .pop, particle: "🎊"),
        StickerDef(id: "think", emoji: "🤔", motion: .tilt),
        StickerDef(id: "sleep", emoji: "😴", motion: .float, particle: "💤"),
        StickerDef(id: "rocket", emoji: "🚀", motion: .fly, particle: "🔥"),
        StickerDef(id: "star", emoji: "🌟", motion: .spin, particle: "✨"),
        StickerDef(id: "melon", emoji: "🍉", motion: .bounce),
        StickerDef(id: "clap", emoji: "👏", motion: .shake, particle: "🎊"),
    ]

    /// Android's empty-chat greeting characters; here shown with their emoji.
    static let greetings: [StickerDef] = [
        StickerDef(id: "greet_cat", emoji: "🐱", caption: "Салом!", colors: [Color(hex: 0xFF9F43), Color(hex: 0xEE5A24)], motion: .wave),
        StickerDef(id: "greet_bear", emoji: "🐻", caption: "Хуш омадед!", colors: [Color(hex: 0xB07A4F), Color(hex: 0x7A4B2A)], motion: .bounce),
        StickerDef(id: "greet_penguin", emoji: "🐧", caption: "Салом-салом!", colors: [Color(hex: 0x4F8DFF), Color(hex: 0x2F3A56)], motion: .tilt),
        StickerDef(id: "greet_bunny", emoji: "🐰", caption: "Чӣ хел шумо?", colors: [Color(hex: 0xFF8FB1), Color(hex: 0xD9467A)], motion: .bounce),
        StickerDef(id: "greet_chick", emoji: "🐥", caption: "Рӯз ба хайр!", colors: [Color(hex: 0xFFC93C), Color(hex: 0xF08A24)], motion: .pop),
    ]

    /// "Дух S" - Safir's mascot, animated WebP shared with Android (app/src/main/assets/spirit_stickers).
    static let spiritPack: [StickerDef] = [
        ("greet", "👻"), ("wave", "👋"), ("love", "💙"), ("question", "❓"), ("wow", "❗"), ("cool", "😎"),
        ("sleep", "😴"), ("peek", "👀"), ("mail", "✉️"), ("laugh", "😂"), ("laptop", "💻"),
    ].map { StickerDef(id: "spirit_\($0.0)", emoji: $0.1, webp: "spirit_\($0.0)") }

    private static let byId = Dictionary(uniqueKeysWithValues: (pack + greetings + spiritPack).map { ($0.id, $0) })

    static func token(_ id: String) -> String { "[sticker:\(id)]" }

    /// The sticker this message content represents, or nil for ordinary text.
    static func from(content: String) -> StickerDef? {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("[sticker:"), t.hasSuffix("]") else { return nil }
        let id = String(t.dropFirst("[sticker:".count).dropLast())
        guard id.count <= 32, id.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" }) else { return nil }
        if id.hasPrefix("ae_") { return animated(key: String(id.dropFirst(3))) }
        return byId[id]
    }

    /// Animated emoji sticker "[sticker:ae_<code points>]" (UI/AnimatedEmoji.swift, Android Stickers.kt).
    static func animated(key: String) -> StickerDef? {
        let scalars = key.split(separator: "_").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
        guard !scalars.isEmpty else { return nil }
        return StickerDef(id: "ae_" + key, emoji: String(String.UnicodeScalarView(scalars)))
    }

    static var animatedPack: [StickerDef] {
        AnimatedEmoji.all.compactMap { animated(key: AnimatedEmoji.key($0)) }
    }

    var isAnimatedEmoji: Bool { id.hasPrefix("ae_") }
}

/// One sticker, animated forever (the motion of its definition) with a few floating particles.
struct StickerView: View {
    let sticker: StickerDef
    var size: CGFloat = 150
    @State private var playing = true
    @State private var playToken = 0

    var body: some View {
        Group {
            if sticker.isAnimatedEmoji {
                AnimatedEmojiView(emoji: sticker.emoji, size: size, replay: playToken)
            } else if let webp = sticker.webp {
                AnimatedWebPView(name: webp, playing: playing).frame(width: size, height: size)
            } else {
                drawn
            }
        }
        // Plays when it shows and again on tap (Telegram), not forever.
        .task(id: playToken) {
            playing = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            playing = false
        }
        // Simultaneous, so a sticker inside a button (the panel) still sends.
        .simultaneousGesture(TapGesture().onEnded { playToken += 1 })
    }

    private var drawn: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                face(t)
                if let particle = sticker.particle {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = (t * 0.6 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                        Text(particle).font(.system(size: size * 0.12))
                            .offset(x: CGFloat(sin(Double(i) * 1.7 + t)) * size * 0.32,
                                    y: size * 0.3 - CGFloat(phase) * size * 0.7)
                            .opacity(1 - phase)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(sticker.caption ?? sticker.emoji)
    }

    @ViewBuilder
    private func face(_ t: Double) -> some View {
        if let caption = sticker.caption {
            VStack(spacing: 4) {
                Text(sticker.emoji).font(.system(size: size * 0.42))
                    .modifier(StickerMotionEffect(motion: sticker.motion, t: t))
                Text(caption).font(.system(size: size * 0.11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: sticker.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: (sticker.colors.first ?? .black).opacity(0.35), radius: 10, y: 4)
        } else {
            Text(sticker.emoji).font(.system(size: size * 0.7))
                .modifier(StickerMotionEffect(motion: sticker.motion, t: t))
                .frame(width: size, height: size)
        }
    }
}

private struct StickerMotionEffect: ViewModifier {
    let motion: StickerDef.Motion
    let t: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        switch motion {
        case .beat: content.scaleEffect(1 + 0.12 * max(0, sin(t * 6)))
        case .bounce: content.offset(y: -10 * abs(sin(t * 3)))
        case .shake: content.rotationEffect(.degrees(8 * sin(t * 14)))
        case .float: content.offset(y: 6 * sin(t * 3))
        case .wave: content.rotationEffect(.degrees(18 * sin(t * 3)), anchor: .bottom)
        case .spin: content.rotationEffect(.degrees((t * 90).truncatingRemainder(dividingBy: 360)))
        case .pop: content.scaleEffect(1 + 0.15 * abs(sin(t * 2.5)))
        case .fly: content.offset(x: 6 * sin(t * 3), y: -6 * abs(sin(t * 2)))
        case .tilt: content.rotationEffect(.degrees(10 * sin(t * 3)))
        }
    }
}

/// Plays an animated WebP from the bundle (UIImageView - SwiftUI's Image shows one frame only).
/// Frames are decoded once per file and kept, like Android's AnimatedImageDrawable.
struct AnimatedWebPView: UIViewRepresentable {
    let name: String
    var playing = true

    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let name = name
        if let cached = Self.cache.object(forKey: name as NSString) {
            view.image = cached
        } else {
            Task.detached(priority: .userInitiated) {
                guard let image = Self.load(name) else { return }
                Self.cache.setObject(image, forKey: name as NSString)
                await MainActor.run { view.image = image; if playing { view.startAnimating() } }
            }
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if playing { view.startAnimating() } else { view.stopAnimating() }
    }

    nonisolated private static func load(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "webp", subdirectory: "spirit_stickers"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var duration = 0.0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let webp = props?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
            duration += (webp?[kCGImagePropertyWebPUnclampedDelayTime] as? Double)
                ?? (webp?[kCGImagePropertyWebPDelayTime] as? Double) ?? 0.05
        }
        guard !frames.isEmpty else { return nil }
        return frames.count == 1 ? frames[0] : UIImage.animatedImage(with: frames, duration: duration)
    }
}
