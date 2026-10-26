import Lottie
import SwiftUI

/// Telegram-style animated emoji: Google Noto Animated Emoji (Lottie, CC BY 4.0) bundled from
/// app/src/main/assets/animated_emoji (scripts/fetch_animated_emoji.py) - the same files Android
/// plays. File name = the emoji's code points in hex joined by "_", without FE0F.
enum AnimatedEmoji {
    private static let folder = "animated_emoji"

    /// Names of the bundled animations, read once.
    private static let available: Set<String> = {
        guard let dir = Bundle.main.url(forResource: folder, withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return Set(files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
    }()

    @MainActor private static var cache: [String: LottieAnimation] = [:]

    static func key(_ emoji: String) -> String {
        emoji.unicodeScalars.filter { $0.value != 0xFE0F }.map { String($0.value, radix: 16) }.joined(separator: "_")
    }

    static func has(_ emoji: String) -> Bool { available.contains(key(emoji)) }

    /// Every bundled emoji as text, for the sticker panel.
    static var all: [String] {
        available.sorted().compactMap { name in
            let scalars = name.split(separator: "_").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
            guard !scalars.isEmpty else { return nil }
            var s = String(String.UnicodeScalarView(scalars))
            // ❤️ ✌️ and friends need FE0F back to draw as emoji when there's no animation.
            if scalars.count == 1, scalars[0].value < 0x2800 { s += "\u{FE0F}" }
            return s
        }
    }

    @MainActor
    static func animation(_ emoji: String) -> LottieAnimation? {
        let k = key(emoji)
        if let hit = cache[k] { return hit }
        guard available.contains(k),
              let url = Bundle.main.url(forResource: k, withExtension: "json", subdirectory: folder),
              let animation = LottieAnimation.filepath(url.path) else { return nil }
        cache[k] = animation
        return animation
    }

    /// The emoji of a message that is only 1-3 emoji with animations (Telegram shows those big).
    static func bigEmoji(in text: String) -> [String]? {
        let chars = text.filter { !$0.isWhitespace }.map(String.init)
        guard (1...3).contains(chars.count), chars.allSatisfy(has) else { return nil }
        return chars
    }
}

/// One animated emoji; falls back to the plain glyph. [replay] restarts it when changed.
struct AnimatedEmojiView: View {
    let emoji: String
    var size: CGFloat = 32
    var loop = false
    var replay = 0

    var body: some View {
        Group {
            if !AppSettings.shared.reduceAnimations, let animation = AnimatedEmoji.animation(emoji) {
                LottieView(animation: animation)
                    .playing(loopMode: loop ? .loop : .playOnce)
                    .resizable()
                    .id(replay)
            } else {
                Text(emoji).font(.system(size: size * 0.82))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(emoji))
    }
}

/// A message that is only emoji: big and animated with no bubble, tap plays it again (Telegram).
struct BigEmojiMessage: View {
    let emoji: [String]
    @State private var replay = 0

    private var size: CGFloat { emoji.count == 1 ? 120 : emoji.count == 2 ? 92 : 74 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(emoji.enumerated()), id: \.offset) { _, e in
                AnimatedEmojiView(emoji: e, size: size, replay: replay)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            replay += 1
        }
    }
}
