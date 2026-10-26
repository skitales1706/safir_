import SwiftUI
import UIKit

/// Safir palette - the colours of the current theme (Settings → Оформление; Android AppThemes).
/// Classic resolves for light or dark mode on its own. Views that draw with these redraw when
/// the theme or the bubble colour changes.
enum Safir {
    static var palette: ThemePalette { ThemeRuntime.shared.palette }
    static var accent: Color { palette.accent }
    static var accentDeep: Color { palette.accentDeep }
    static var background: Color { palette.background }
    static var backgroundMid: Color { palette.backgroundMid }
    static var surface: Color { palette.surface }
    static var card: Color { palette.card }
    static var text: Color { palette.text }
    static var muted: Color { palette.muted }
    static let online = dynamic(light: 0x1FAE6B, dark: 0x3DD68C)
    static var bubbleIn: Color { palette.bubbleIn }
    static var bubbleOut: Color { ThemeRuntime.shared.bubble.top }
    static var bubbleOutDeep: Color { ThemeRuntime.shared.bubble.bottom }
    static var metaIn: Color { palette.metaIn }
    static var metaOut: Color { ThemeRuntime.shared.bubble.meta }
    static var separator: Color { palette.separator }
    static let danger = Color(red: 0.93, green: 0.30, blue: 0.33)

    static let brandGradient = LinearGradient(colors: [Color(hex: 0x1ECFEF), Color(hex: 0x0E7A90)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Settings → Оформление → "Вибрация при нажатии".
    static let hapticsKey = "safir.haptics"

    /// Light tap feedback - sending, reacting, toggles.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

/// Telegram-style bubble: rounded, with a small tail at the bottom on the sender's side for the
/// last message of a group.
struct BubbleShape: Shape {
    let isMe: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 17
        let small: CGFloat = 6
        var p = Path()
        let w = rect.width, h = rect.height
        let bl: CGFloat = isMe ? r : small
        let br: CGFloat = isMe ? small : r
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        if isMe && tail {
            p.addLine(to: CGPoint(x: w, y: h - 8))
            p.addQuadCurve(to: CGPoint(x: w + 6, y: h), control: CGPoint(x: w, y: h))
            p.addQuadCurve(to: CGPoint(x: w - 12, y: h - 2), control: CGPoint(x: w - 4, y: h))
        } else {
            p.addLine(to: CGPoint(x: w, y: h - br))
            p.addQuadCurve(to: CGPoint(x: w - br, y: h), control: CGPoint(x: w, y: h))
        }
        if !isMe && tail {
            p.addLine(to: CGPoint(x: 12, y: h - 2))
            p.addQuadCurve(to: CGPoint(x: -6, y: h), control: CGPoint(x: 4, y: h))
            p.addQuadCurve(to: CGPoint(x: 0, y: h - 8), control: CGPoint(x: 0, y: h))
        } else {
            p.addLine(to: CGPoint(x: bl, y: h))
            p.addQuadCurve(to: CGPoint(x: 0, y: h - bl), control: CGPoint(x: 0, y: h))
        }
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Three bouncing dots - "печатает…".
struct TypingDots: View {
    var color: Color = Safir.accent
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle().fill(color).frame(width: 5, height: 5)
                    .offset(y: phase ? -3 : 1)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        // Started on the next runloop: toggled inside the appear transaction, the repeating
        // animation also caught the parent's layout and the dots drifted across the screen.
        .onAppear { DispatchQueue.main.async { phase = true } }
    }
}

/// Buttons that shrink a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Date chip between days of messages.
struct DateChip: View {
    let millis: Int64

    var body: some View {
        Text(Self.title(millis))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.28)))
            .padding(.vertical, 6)
    }

    static func title(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))
    }

    static func sameDay(_ a: Int64, _ b: Int64) -> Bool {
        Calendar.current.isDate(Date(timeIntervalSince1970: TimeInterval(a) / 1000),
                                inSameDayAs: Date(timeIntervalSince1970: TimeInterval(b) / 1000))
    }
}

/// The Safir mark: gradient tile with a paper plane - login hero and launch screen.
struct SafirLogo: View {
    var size: CGFloat = 96
    @State private var glow = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Safir.brandGradient)
                .shadow(color: Color(hex: 0x1ECFEF).opacity(glow ? 0.55 : 0.25), radius: glow ? 24 : 12)
            Image(systemName: "paperplane.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-12))
                .offset(x: -size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

/// Launch: the logo pops in, then the app fades in under it.
struct SplashView: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Safir.background.ignoresSafeArea()
            VStack(spacing: 18) {
                SafirLogo(size: 110)
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)
                Text("Safir").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Safir.text)
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { shown = true } }
    }
}
