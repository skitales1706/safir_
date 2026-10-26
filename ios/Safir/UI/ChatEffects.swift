import SwiftUI

// MARK: - Dust (Android DustEffect: a deleted message crumbles away, Telegram's "Thanos" delete)

/// Drives the removal: the bubble blurs, fades and drifts up-right while a cloud of specks in the
/// accent colour scatters from it. Seeded per message so every bubble breaks differently.
struct DustEffect: ViewModifier, Animatable {
    var progress: Double
    let seed: Int

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: progress * 6)
            .opacity(1 - progress)
            .offset(x: progress * 18, y: -progress * 22)
            .overlay {
                if progress > 0.001 && progress < 0.999 {
                    DustCloud(progress: progress, seed: seed).allowsHitTesting(false)
                }
            }
    }
}

private struct DustCloud: View {
    let progress: Double
    let seed: Int

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed))
            for _ in 0..<70 {
                let start = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
                // Specks further right leave later, like the sweep in Telegram.
                let delay = Double(start.x / max(size.width, 1)) * 0.35
                let t = max(0, min(1, (progress - delay) / (1 - delay)))
                let angle = -Double.pi / 2 + (rng.next() - 0.3) * 1.6
                let distance = 30 + rng.next() * 60
                let r = 1 + rng.next() * 2
                let accent = rng.next() > 0.5
                guard t > 0 else { continue }
                let p = CGPoint(x: start.x + cos(angle) * distance * t, y: start.y + sin(angle) * distance * t)
                context.opacity = (1 - t) * 0.9
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(accent ? Safir.accent : Safir.muted))
            }
        }
    }
}

/// Tiny deterministic generator (xorshift) so a bubble's specks don't jump between frames.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

extension AnyTransition {
    /// Removal for deleted messages; respects "Reduce animations".
    static func dust(seed: Int) -> AnyTransition {
        if AppSettings.shared.reduceAnimations { return .opacity }
        return .modifier(active: DustEffect(progress: 1, seed: seed), identity: DustEffect(progress: 0, seed: seed))
    }
}

// MARK: - Reaction burst (Android ReactionAnimations)

/// The picked emoji pops big over the bubble and a ring of small copies flies out.
struct ReactionBurst: View {
    let emoji: String
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Text(emoji).font(.system(size: 14))
                    .offset(x: go ? cos(angle) * 46 : 0, y: go ? sin(angle) * 46 : 0)
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 0.4 : 1)
            }
            if AnimatedEmoji.has(emoji) {
                // Telegram's reaction effect: the animated emoji plays big over the message.
                AnimatedEmojiView(emoji: emoji, size: 110)
                    .scaleEffect(go ? 1 : 0.3)
            } else {
                Text(emoji).font(.system(size: 44))
                    .scaleEffect(go ? 1.25 : 0.2)
                    .opacity(go ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { go = true }
        }
    }
}
