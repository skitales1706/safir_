import SwiftUI

/// Weather (Android WeatherScreen): live animated sky, big temperature, 24 hours, 7 days and
/// details for any city or district centre of Tajikistan.
struct WeatherView: View {
    private var store: ServicesStore { .shared }
    @State private var picking = false

    var body: some View {
        ZStack {
            if let city = store.city {
                SkyView(kind: WeatherKind(code: city.current.code), day: city.current.isDay)
                    .ignoresSafeArea()
                    .id(city.id)
                    .transition(.opacity)
                ScrollView {
                    content(city)
                }
                .refreshable { await store.load(force: true) }
            } else {
                Safir.brandGradient.ignoresSafeArea()
                if store.loading {
                    ProgressView().tint(.white)
                } else {
                    EmptyStateView(icon: "cloud.sun", title: "Нет данных о погоде", subtitle: "Проверьте соединение с сервером")
                }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: store.city?.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { picking = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill").font(.caption)
                        Text(store.city?.title ?? "Погода").font(.headline)
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
                }
                .accessibilityIdentifier("weather-city")
            }
        }
        .sheet(isPresented: $picking) { CityPicker() }
        .task { await store.load() }
    }

    private func content(_ city: CityWeather) -> some View {
        let kind = WeatherKind(code: city.current.code)
        let temp = city.current.temp ?? 0
        let lows = city.daily.compactMap { $0.min }
        let highs = city.daily.compactMap { $0.max }
        let weekLow = lows.min() ?? 0
        let weekHigh = highs.max() ?? 1
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Image(systemName: kind.symbol(day: city.current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 60))
                    .symbolEffect(.bounce, value: city.id)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                Text("\(temp)°")
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .contentTransition(.numericText(value: Double(temp)))
                Text(kind.title).font(.title3.weight(.medium))
                if let today = city.today {
                    Text("Макс. \(today.max ?? temp)°  Мин. \(today.min ?? temp)°").font(.subheadline.weight(.medium))
                }
                if let feels = city.current.feelsLike {
                    Text("Ощущается как \(feels)°").font(.subheadline).opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .appearIn(0)

            GlassCard(title: "Почасовой прогноз", icon: "clock") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(Array(city.hourly.prefix(24).enumerated()), id: \.offset) { i, hour in
                            VStack(spacing: 8) {
                                Text(i == 0 ? "Сейчас" : hour.label).font(.footnote.weight(.semibold))
                                Image(systemName: WeatherKind(code: hour.code).symbol(day: hour.isDay))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.title3)
                                    .frame(height: 26)
                                Text(hour.precip >= 20 ? "\(hour.precip)%" : " ")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(Color(hex: 0x9EDBFF))
                                Text("\(hour.temp ?? 0)°").font(.body.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .appearIn(1)

            GlassCard(title: "Прогноз на 7 дней", icon: "calendar") {
                VStack(spacing: 12) {
                    ForEach(Array(city.daily.enumerated()), id: \.offset) { i, day in
                        HStack(spacing: 8) {
                            Text(Self.dayName(day.date, index: i)).font(.body.weight(.medium))
                                .frame(width: 74, alignment: .leading)
                            Image(systemName: WeatherKind(code: day.code).symbol(day: true))
                                .symbolRenderingMode(.multicolor).frame(width: 28)
                            Text(day.precip >= 20 ? "\(day.precip)%" : "")
                                .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: 0x9EDBFF))
                                .frame(width: 34, alignment: .leading)
                            Text("\(day.min ?? 0)°").opacity(0.7).frame(width: 34, alignment: .trailing)
                            TempRangeBar(low: day.min ?? weekLow, high: day.max ?? weekHigh,
                                         rangeLow: weekLow, rangeHigh: weekHigh,
                                         now: i == 0 ? city.current.temp : nil)
                            Text("\(day.max ?? 0)°").frame(width: 34, alignment: .trailing)
                        }
                        .font(.body.monospacedDigit())
                    }
                }
            }
            .appearIn(2)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                DetailTile(icon: "humidity.fill", title: "Влажность", value: city.current.humidity.map { "\($0)%" } ?? "—")
                DetailTile(icon: "wind", title: "Ветер", value: city.current.wind.map { "\($0) км/ч" } ?? "—")
                DetailTile(icon: "gauge.with.dots.needle.33percent", title: "Давление",
                           value: city.current.pressure.map { "\($0) гПа" } ?? "—")
                DetailTile(icon: "sun.max.trianglebadge.exclamationmark", title: "УФ-индекс",
                           value: Self.uvText(city.today?.uv), note: city.today?.uv.map { Self.uvLevel($0) })
                DetailTile(icon: "sunrise.fill", title: "Восход", value: Self.clock(city.today?.sunrise))
                DetailTile(icon: "sunset.fill", title: "Закат", value: Self.clock(city.today?.sunset))
            }
            .appearIn(3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEEEE, d"
        return f
    }()

    static func dayName(_ iso: String, index: Int) -> String {
        if index == 0 { return "Сегодня" }
        guard let date = isoDay.date(from: iso) else { return iso }
        return weekday.string(from: date).capitalized
    }

    /// "2026-10-12T06:41" -> "06:41".
    static func clock(_ iso: String?) -> String {
        guard let iso, let time = iso.split(separator: "T").last else { return "—" }
        return String(time.prefix(5))
    }

    static func uvText(_ uv: Double?) -> String {
        guard let uv else { return "—" }
        return String(format: "%.0f", uv)
    }

    static func uvLevel(_ uv: Double) -> String {
        switch uv {
        case ..<3: return "Низкий"
        case ..<6: return "Умеренный"
        case ..<8: return "Высокий"
        default: return "Очень высокий"
        }
    }
}

/// Frosted card over the sky.
struct GlassCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).textCase(.uppercase).opacity(0.75)
            Rectangle().fill(.white.opacity(0.22)).frame(height: 0.5)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .safirGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

private struct DetailTile: View {
    let icon: String
    let title: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).textCase(.uppercase).opacity(0.75)
            Text(value).font(.title2.weight(.semibold)).contentTransition(.numericText())
            Text(note ?? " ").font(.footnote).opacity(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .safirGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The day's low..high on the week's scale, cold blue to warm orange (iOS Weather style).
private struct TempRangeBar: View {
    let low: Int
    let high: Int
    let rangeLow: Int
    let rangeHigh: Int
    let now: Int?

    var body: some View {
        GeometryReader { geo in
            let span = CGFloat(Swift.max(rangeHigh - rangeLow, 1))
            let width = geo.size.width
            let x0 = width * CGFloat(low - rangeLow) / span
            let x1 = width * CGFloat(high - rangeLow) / span
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x6FD3FF), Color(hex: 0xFFD36F), Color(hex: 0xFF8A3D)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: Swift.max(x1 - x0, 6))
                    .offset(x: x0)
                if let now {
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
                        .offset(x: width * CGFloat(now - rangeLow) / span - 3.5)
                }
            }
        }
        .frame(height: 5)
    }
}

/// All cities by region, with their current temperature.
private struct CityPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var store: ServicesStore { .shared }

    private static let regionIds = ["dushanbe", "sughd", "khatlon", "rrp", "gbao"]
    private static let regionNames = ["Душанбе", "Согдийская область", "Хатлонская область",
                                      "Районы республиканского подчинения", "ГБАО"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.regionIds.indices, id: \.self) { i in
                    let cities = store.weather.filter { $0.region == Self.regionIds[i] && matches($0) }
                    if !cities.isEmpty {
                        Section(Self.regionNames[i]) {
                            ForEach(cities) { city in row(city) }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Город или район")
            .navigationTitle("Город")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
    }

    private func matches(_ city: CityWeather) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || city.title.lowercased().contains(q) || city.name.lowercased().contains(q)
    }

    private func row(_ city: CityWeather) -> some View {
        Button {
            Safir.tap()
            withAnimation(.easeInOut(duration: 0.6)) { store.select(city: city.id) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(city.title).foregroundStyle(Safir.text)
                Spacer()
                Image(systemName: WeatherKind(code: city.current.code).symbol(day: city.current.isDay))
                    .symbolRenderingMode(.multicolor)
                Text("\(city.current.temp ?? 0)°").font(.body.monospacedDigit()).foregroundStyle(Safir.text)
                    .frame(width: 40, alignment: .trailing)
                Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(Safir.accent)
                    .opacity(city.id == store.city?.id ? 1 : 0)
            }
        }
    }
}

// MARK: - Animated sky

/// Sun with turning rays, twinkling stars, drifting clouds, rain, snow, fog and lightning,
/// drawn every frame with Canvas - the background of the weather card and screen.
struct SkyView: View {
    let kind: WeatherKind
    let day: Bool

    var body: some View {
        // Paused in screenshot mode: UI tests wait for the screen to go idle, which never
        // happens while a frame-by-frame animation runs.
        TimelineView(.animation(minimumInterval: nil, paused: DemoData.active)) { timeline in
            Canvas { context, size in
                draw(&context, size, timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(LinearGradient(colors: kind.sky(day: day), startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    /// Stable pseudo-random 0..1 per particle.
    private static func rnd(_ i: Int, _ k: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    private func draw(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        if kind == .clear || kind == .partly {
            if day { sun(&g, s, t) } else { stars(&g, s, t) }
        }
        if kind == .fog { fog(&g, s, t) }
        if kind != .clear {
            let dark = kind == .rain || kind == .storm || kind == .drizzle
            clouds(&g, s, t, count: kind == .partly ? 2 : 4, alpha: dark ? 0.16 : 0.32)
        }
        if kind == .rain || kind == .drizzle || kind == .storm { rain(&g, s, t, heavy: kind != .drizzle) }
        if kind == .snow { snow(&g, s, t) }
        if kind == .storm {
            let phase = t.truncatingRemainder(dividingBy: 7)
            if phase < 0.1 || (phase > 0.22 && phase < 0.3) {
                g.fill(Path(CGRect(origin: .zero, size: s)), with: .color(.white.opacity(0.22)))
            }
        }
    }

    private func sun(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        let c = CGPoint(x: s.width * 0.8, y: Swift.min(s.height * 0.16, 110))
        let glow = 150 * (1 + 0.06 * sin(t * 1.4))
        g.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
               with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF3B0).opacity(0.55), .clear]),
                                     center: c, startRadius: 0, endRadius: glow))
        var rays = Path()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi + t * 0.12
            rays.move(to: CGPoint(x: c.x + cos(a) * 52, y: c.y + sin(a) * 52))
            rays.addLine(to: CGPoint(x: c.x + cos(a) * 76, y: c.y + sin(a) * 76))
        }
        g.stroke(rays, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: c.x - 38, y: c.y - 38, width: 76, height: 76)),
               with: .radialGradient(Gradient(colors: [.white, Color(hex: 0xFFE27A)]),
                                     center: c, startRadius: 0, endRadius: 38))
    }

    private func stars(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        for i in 0..<45 {
            let x = Self.rnd(i, 1) * s.width
            let y = Self.rnd(i, 2) * s.height * 0.6
            let r = 0.6 + Self.rnd(i, 3) * 1.4
            let a = 0.35 + 0.65 * abs(sin(t * (0.4 + Self.rnd(i, 4)) + Double(i)))
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(a)))
        }
    }

    private func clouds(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double, count: Int, alpha: Double) {
        for i in 0..<count {
            let w = 170 + Self.rnd(i, 5) * 130
            let h = w * 0.42
            let speed = 7 + Self.rnd(i, 6) * 9
            let x = (Self.rnd(i, 7) * s.width + t * speed).truncatingRemainder(dividingBy: s.width + w) - w
            let y = s.height * (0.05 + 0.11 * Double(i))
            var p = Path()
            p.addEllipse(in: CGRect(x: x, y: y + h * 0.3, width: w, height: h * 0.7))
            p.addEllipse(in: CGRect(x: x + w * 0.15, y: y, width: w * 0.45, height: h * 0.8))
            p.addEllipse(in: CGRect(x: x + w * 0.45, y: y + h * 0.1, width: w * 0.4, height: h * 0.7))
            g.fill(p, with: .color(.white.opacity(alpha)))
        }
    }

    private func rain(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double, heavy: Bool) {
        var p = Path()
        for i in 0..<(heavy ? 90 : 45) {
            let speed = 420 + Self.rnd(i, 8) * 220
            let x = Self.rnd(i, 9) * (s.width + 40)
            let y = (Self.rnd(i, 10) * s.height + t * speed).truncatingRemainder(dividingBy: s.height + 40) - 20
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x - 4, y: y + (heavy ? 18 : 11)))
        }
        g.stroke(p, with: .color(.white.opacity(0.38)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    private func snow(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        for i in 0..<60 {
            let speed = 26 + Self.rnd(i, 11) * 40
            let y = (Self.rnd(i, 12) * s.height + t * speed).truncatingRemainder(dividingBy: s.height + 10) - 5
            let x = Self.rnd(i, 13) * s.width + sin(t * 0.8 + Double(i)) * 12
            let r = 1.5 + Self.rnd(i, 14) * 2.5
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)))
        }
    }

    private func fog(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        for i in 0..<4 {
            let x = sin(t * 0.15 + Double(i)) * 40 - s.width * 0.2
            let y = s.height * (0.15 + 0.12 * Double(i))
            g.fill(Path(roundedRect: CGRect(x: x, y: y, width: s.width * 1.4, height: 38), cornerRadius: 19),
                   with: .color(.white.opacity(0.12)))
        }
    }
}
