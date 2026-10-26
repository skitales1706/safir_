import SwiftUI

/// Ёвар - the code-drawn robot mascot, ported from Android's EvvarRobot.kt (same 220x240 design
/// space and colours). Idles on its own: hovers, blinks, looks around, springy antenna, flickering
/// jet, waves now and then. Interactive: eyes and body follow a dragging finger, tap = jump + wave
/// + hearts + speech bubble, long press = spin. `thinking` shows the busy face with orbiting dots;
/// bumping `waveKey` makes it wave.
struct EvvarRobot: View {
    var interactive = true
    var thinking = false
    var waveKey = 0

    @State private var motion = RobotMotion()
    @State private var phrase: String?

    private static let phrases = ["Привет! 👋", "Я Ёвар!", "Чем помочь?", "Хи-хи, щекотно! 😄", "Задай вопрос!"]

    var body: some View {
        GeometryReader { geo in
            // Paused in screenshot mode: UI tests wait for an idle screen.
            TimelineView(.animation(minimumInterval: nil, paused: DemoData.active)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    motion.step(t: t, thinking: thinking)
                    RobotPainter(m: motion, t: t, thinking: thinking).draw(&context, size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if interactive { poke() } }
            .onLongPressGesture {
                guard interactive else { return }
                Safir.tap(.medium)
                motion.pendingSpin = true
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { v in
                        let x = (v.location.x / Swift.max(geo.size.width, 1) - 0.5) * 2
                        let y = (v.location.y / Swift.max(geo.size.height, 1) - 0.4) * 2
                        motion.target = CGPoint(x: Swift.min(Swift.max(x, -1), 1), y: Swift.min(Swift.max(y, -1), 1))
                    }
                    .onEnded { _ in motion.target = nil },
                including: interactive ? .all : .none)
        }
        .overlay(alignment: .top) {
            if let phrase {
                Text(phrase)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x0B1A33))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: phrase)
        .onChange(of: waveKey) { _, key in
            if key > 0 { motion.pendingWave = true }
        }
        .accessibilityLabel("Ёвар")
    }

    private func poke() {
        Safir.tap(.medium)
        motion.pendingPoke = true
        let said = Self.phrases.randomElement()
        phrase = said
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if phrase == said { phrase = nil }
        }
    }
}

/// Animation state advanced once per frame inside the Canvas (a class, so drawing can update it
/// without re-rendering the view). Taps set the `pending` flags; the next frame starts them.
final class RobotMotion {
    struct Particle {
        let vx: Double
        let vy: Double
        let born: Double
        let heart: Bool
    }

    var target: CGPoint?
    var pendingWave = false
    var pendingPoke = false
    var pendingSpin = false

    private(set) var lookX = 0.0
    private(set) var lookY = 0.0
    private(set) var particles: [Particle] = []
    private var lastT = 0.0
    private var nextBlink = 0.0
    private var blinkAt = -10.0
    private var doubleBlink = false
    private var nextWave = 0.0
    private var waveAt = -10.0
    private var jumpAt = -10.0
    private var spinAt = -10.0
    private var happyUntil = -10.0

    func step(t: Double, thinking: Bool) {
        if lastT == 0 {
            lastT = t
            nextBlink = t + .random(in: 2.2...5.2)
            nextWave = t + .random(in: 7...11)
        }
        let dt = Swift.min(Swift.max(t - lastT, 0), 0.1)
        lastT = t
        if t >= nextBlink {
            blinkAt = t
            doubleBlink = Int.random(in: 0..<4) == 0
            nextBlink = t + .random(in: 2.2...5.2)
        }
        if t >= nextWave {
            waveAt = t
            nextWave = t + .random(in: 7...11)
        }
        if pendingWave {
            pendingWave = false
            waveAt = t
        }
        if pendingPoke {
            pendingPoke = false
            happyUntil = t + 1.8
            jumpAt = t
            waveAt = t
            for i in 0..<7 {
                let a = -Double.pi / 2 + Double(i - 3) * 0.35
                particles.append(Particle(vx: cos(a) * 60, vy: sin(a) * 90, born: t, heart: i % 2 == 0))
            }
        }
        if pendingSpin {
            pendingSpin = false
            spinAt = t
            happyUntil = t + 1.5
        }
        let goal = target ?? (thinking ? CGPoint(x: 0.55, y: -0.7)
                                       : CGPoint(x: sin(t * 0.7) * 0.5, y: sin(t * 0.45 + 1) * 0.3))
        let k = Swift.min(1, dt * 7)
        lookX += (Double(goal.x) - lookX) * k
        lookY += (Double(goal.y) - lookY) * k
        particles.removeAll { t - $0.born > 1.6 }
    }

    func blink(_ t: Double) -> Double {
        func shut(_ age: Double) -> Double? {
            if age < 0 { return nil }
            if age < 0.09 { return 1 - 0.92 * age / 0.09 }
            if age < 0.22 { return 0.08 + 0.92 * (age - 0.09) / 0.13 }
            return nil
        }
        let age = t - blinkAt
        return shut(age) ?? (doubleBlink ? shut(age - 0.34) : nil) ?? 1
    }

    func wave(_ t: Double) -> Double {
        let age = t - waveAt
        if age < 0 { return 0 }
        if age < 0.25 { return age / 0.25 }
        if age < 1.65 { return 1 }
        if age < 2.0 { return 1 - (age - 1.65) / 0.35 }
        return 0
    }

    func jump(_ t: Double) -> Double {
        let age = t - jumpAt
        if age < 0 || age > 2 { return 0 }
        if age < 0.16 { return -26 * age / 0.16 }
        return -26 * exp(-(age - 0.16) * 5) * cos((age - 0.16) * 16)
    }

    func spin(_ t: Double) -> Double {
        let age = t - spinAt
        if age < 0 || age > 0.9 { return 0 }
        let p = age / 0.9
        let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        return 360 * eased
    }

    func happy(_ t: Double) -> Bool { t < happyUntil }
}

/// One frame of the robot, in Android's design coordinates.
private struct RobotPainter {
    let m: RobotMotion
    let t: Double
    let thinking: Bool

    static let cyan = Color(hex: 0x22D3EE)
    static let blue = Color(hex: 0x3B82F6)
    static let pink = Color(hex: 0xFF6FA8)
    static let gold = Color(hex: 0xFACC15)
    static let shellTop = Color(hex: 0xF7FAFF)
    static let shellBottom = Color(hex: 0xB7C9E6)
    static let faceTop = Color(hex: 0x0B1A33)
    static let faceBottom = Color(hex: 0x13306A)
    static let joint = Color(hex: 0x9CB3D6)
    static let neck = Color(hex: 0x8FA6C8)

    func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let s = Swift.min(size.width / 220, size.height / 240)
        var g = context
        g.translateBy(x: size.width / 2, y: size.height / 2 - 4 * s)
        g.scaleBy(x: s, y: s)
        robot(g)
        for p in m.particles { particle(g, p) }
    }

    // MARK: Helpers

    private func rotated(_ g: GraphicsContext, _ degrees: Double, around p: CGPoint) -> GraphicsContext {
        var c = g
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .degrees(degrees))
        c.translateBy(x: -p.x, y: -p.y)
        return c
    }

    private func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    private func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func vertical(_ top: Color, _ bottom: Color, _ y0: Double, _ y1: Double) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
    }

    private func glow(_ g: GraphicsContext, _ color: Color, _ x: Double, _ y: Double, _ r: Double) {
        g.fill(circle(x, y, r), with: .radialGradient(Gradient(colors: [color, .clear]), center: CGPoint(x: x, y: y),
                                                     startRadius: 0, endRadius: r))
    }

    /// Android drawArc: angles in degrees clockwise from 3 o'clock, inside the oval `rect`.
    private func arc(_ rect: CGRect, start: Double, sweep: Double, toCenter: Bool) -> Path {
        var p = Path()
        if toCenter { p.move(to: .zero) }
        p.addArc(center: .zero, radius: 1, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
        if toCenter { p.closeSubpath() }
        return p.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width / 2, y: rect.height / 2))
    }

    // MARK: Robot

    private func robot(_ g: GraphicsContext) {
        let hover = sin(t * 1.8) * 6 + m.jump(t)
        let lean = m.lookX * 6
        let headTilt = m.lookX * 9 + sin(t * 0.9) * 3
        let happy = m.happy(t)
        let wave = m.wave(t)

        // Ground shadow shrinks as the robot rises.
        let ss = 1 - Swift.max(-hover, 0) / 60
        g.fill(Path(ellipseIn: CGRect(x: -38 * ss, y: 104, width: 76 * ss, height: 12)), with: .color(.black.opacity(0.22 * ss)))

        var b = g
        b.translateBy(x: 0, y: hover)
        b = rotated(b, lean + m.spin(t), around: CGPoint(x: 0, y: 40))

        // Jet flame.
        let flame = 18 + sin(t * 30) * 3 + sin(t * 17) * 2
        var fp = Path()
        fp.move(to: CGPoint(x: -12, y: 78))
        fp.addQuadCurve(to: CGPoint(x: 12, y: 78), control: CGPoint(x: 0, y: 78 + flame * 2.2))
        fp.closeSubpath()
        b.fill(fp, with: .linearGradient(Gradient(colors: [Self.cyan, Self.blue.opacity(0.6), .clear]),
                                         startPoint: CGPoint(x: 0, y: 78), endPoint: CGPoint(x: 0, y: 78 + flame * 2)))
        glow(b, Self.cyan.opacity(0.45), 0, 84, 26)

        // Arms behind the body: left relaxed, right waves.
        let sway = sin(t * 1.8) * 6
        arm(b, CGPoint(x: -40, y: 30), 22 + sway)
        let waveAngle = -150 + sin(t * 14) * 22
        arm(b, CGPoint(x: 40, y: 30), -(22 + sway) * (1 - wave) + waveAngle * wave)

        // Body with glowing core.
        b.fill(roundRect(-40, 12, 80, 68, 32), with: vertical(Self.shellTop, Self.shellBottom, 12, 80))
        b.fill(roundRect(-26, 18, 30, 8, 4), with: .color(.white.opacity(0.6)))
        let core = 0.6 + 0.4 * (sin(t * (thinking ? 8 : 3)) + 1) / 2
        let coreColor = happy ? Self.pink : Self.cyan
        glow(b, coreColor.opacity(0.7 * core), 0, 48, 20)
        b.fill(circle(0, 48, 10), with: .color(Self.faceTop))
        b.fill(circle(0, 48, 6), with: .color(coreColor.opacity(core)))

        // Neck.
        b.fill(roundRect(-10, 4, 20, 12, 5), with: .color(Self.neck))

        head(rotated(b, headTilt, around: CGPoint(x: 0, y: 6)), headTilt: headTilt, happy: happy)
    }

    private func arm(_ g: GraphicsContext, _ shoulder: CGPoint, _ degrees: Double) {
        let a = rotated(g, degrees, around: shoulder)
        let x = Double(shoulder.x), y = Double(shoulder.y)
        a.fill(roundRect(x - 6, y, 12, 32, 6), with: vertical(Self.shellTop, Self.shellBottom, y, y + 34))
        a.fill(circle(x, y + 36, 8.5), with: .color(Self.joint))
        a.fill(circle(x, y + 36, 3), with: .color(Self.cyan.opacity(0.6)))
    }

    private func head(_ h: GraphicsContext, headTilt: Double, happy: Bool) {
        // Antenna with spring sway.
        let sway = sin(t * 2.3) * 5 - headTilt * 0.8
        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: -70))
        stem.addLine(to: CGPoint(x: sway, y: -94))
        h.stroke(stem, with: .color(Self.neck), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let pulse = 1 + 0.15 * sin(t * 4)
        let ballColor = happy ? Self.pink : Self.cyan
        glow(h, ballColor.opacity(0.6), sway, -98, 18 * pulse)
        h.fill(circle(sway, -98, 7), with: .color(ballColor))
        if thinking && !happy {
            // Cyan <-> gold while busy.
            h.fill(circle(sway, -98, 7), with: .color(Self.gold.opacity((sin(t * 6) + 1) / 2)))
        }
        h.fill(circle(sway - 2, -100, 2.5), with: .color(.white.opacity(0.8)))
        if thinking {
            for i in 0..<3 {
                let a = t * 4 + Double(i) * 2 * .pi / 3
                h.fill(circle(sway + cos(a) * 16, -98 + sin(a) * 9, 3), with: .color(Self.gold.opacity(0.9)))
            }
        }

        // Ears.
        for side in [-1.0, 1.0] {
            h.fill(circle(side * 57, -30, 11), with: .color(Self.joint))
            h.fill(circle(side * 57, -30, 5), with: .color(Self.cyan.opacity(0.8)))
        }

        // Helmet and face screen.
        h.fill(roundRect(-55, -72, 110, 84, 40), with: vertical(Self.shellTop, Self.shellBottom, -72, 12))
        h.fill(roundRect(-36, -66, 34, 7, 4), with: .color(.white.opacity(0.7)))
        h.fill(roundRect(-43, -58, 86, 60, 26), with: vertical(Self.faceTop, Self.faceBottom, -58, 2))
        h.fill(roundRect(-36, -54, 40, 10, 5), with: .color(.white.opacity(0.08)))

        face(h, happy: happy)
    }

    private func face(_ h: GraphicsContext, happy: Bool) {
        let eyeDx = m.lookX * 7
        let eyeDy = m.lookY * 5
        let blink = m.blink(t)
        for side in [-1.0, 1.0] {
            let cx = side * 18 + eyeDx
            let cy = -32 + eyeDy
            if happy {
                // ^ ^ happy eyes.
                h.stroke(arc(CGRect(x: cx - 9, y: cy - 4, width: 18, height: 16), start: 200, sweep: 140, toCenter: false),
                         with: .color(Self.cyan), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            } else {
                let eh = 20 * blink
                h.fill(Path(ellipseIn: CGRect(x: cx - 11, y: cy - eh / 2 - 3, width: 22, height: eh + 6)),
                       with: .color(Self.cyan.opacity(0.25)))
                h.fill(Path(ellipseIn: CGRect(x: cx - 7, y: cy - eh / 2, width: 14, height: eh)), with: .color(Self.cyan))
                if blink > 0.5 {
                    h.fill(circle(cx + 2.5, cy - eh / 4, 2.5), with: .color(.white.opacity(0.9)))
                }
            }
        }

        // Blush.
        let blush = happy ? 0.55 : 0.18
        h.fill(circle(-31, -15, 6), with: .color(Self.pink.opacity(blush)))
        h.fill(circle(31, -15, 6), with: .color(Self.pink.opacity(blush)))

        // Mouth: talking while thinking, big smile when happy, soft smile otherwise.
        let mx = eyeDx * 0.5
        let my = -12 + eyeDy * 0.3
        if thinking {
            let open = 2 + 5 * abs(sin(t * 12))
            h.fill(Path(ellipseIn: CGRect(x: mx - 6, y: my - open / 2, width: 12, height: open)), with: .color(Self.cyan))
        } else if happy {
            h.fill(arc(CGRect(x: mx - 10, y: my - 6, width: 20, height: 14), start: 0, sweep: 180, toCenter: true),
                   with: .color(Self.cyan))
        } else {
            h.stroke(arc(CGRect(x: mx - 8, y: my - 7, width: 16, height: 10), start: 20, sweep: 140, toCenter: false),
                     with: .color(Self.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// Hearts and stars thrown up by a tap.
    private func particle(_ g: GraphicsContext, _ p: RobotMotion.Particle) {
        let age = t - p.born
        guard age >= 0, age <= 1.6 else { return }
        let x = p.vx * age
        let y = -70 + p.vy * age + 40 * age * age
        let alpha = Swift.min(Swift.max(1 - age / 1.6, 0), 1)
        let scale = 0.6 + age * 0.6
        var path = Path()
        if p.heart {
            let r = 5 * scale
            path.move(to: CGPoint(x: x, y: y + r * 1.4))
            path.addCurve(to: CGPoint(x: x, y: y - r * 0.6), control1: CGPoint(x: x - r * 2.2, y: y - r * 0.2),
                          control2: CGPoint(x: x - r * 1.1, y: y - r * 1.8))
            path.addCurve(to: CGPoint(x: x, y: y + r * 1.4), control1: CGPoint(x: x + r * 1.1, y: y - r * 1.8),
                          control2: CGPoint(x: x + r * 2.2, y: y - r * 0.2))
            path.closeSubpath()
            g.fill(path, with: .color(Self.pink.opacity(alpha)))
        } else {
            let r = 6 * scale
            let pts: [(Double, Double)] = [(0, -r), (r * 0.25, -r * 0.25), (r, 0), (r * 0.25, r * 0.25),
                                           (0, r), (-r * 0.25, r * 0.25), (-r, 0), (-r * 0.25, -r * 0.25)]
            path.move(to: CGPoint(x: x + pts[0].0, y: y + pts[0].1))
            for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: x + pt.0, y: y + pt.1)) }
            path.closeSubpath()
            g.fill(path, with: .color(Self.gold.opacity(alpha)))
        }
    }
}
