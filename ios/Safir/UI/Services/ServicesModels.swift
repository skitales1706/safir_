import Observation
import SwiftUI
import WidgetKit

// MARK: - Server data (public endpoints in backend routers/news.py and routers/weather.py)

/// GET /services/exchange - National Bank of Tajikistan rates ("rate" TJS for "unit" units).
struct ExchangeDTO: Decodable {
    let date: String
    let rates: [RateDTO]
}

struct RateDTO: Decodable, Hashable, Identifiable {
    let code: String
    let name: String
    let unit: Int
    let rate: String
    var id: String { code }

    /// TJS for one unit.
    var perUnit: Double { (Double(rate) ?? 0) / Double(Swift.max(unit, 1)) }

    /// USD -> 🇺🇸 (the first two letters of an ISO currency code are the country).
    var flag: String {
        String(code.prefix(2).unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(Character.init))
    }
}

/// GET /services/news.
struct NewsDTO: Decodable, Hashable, Identifiable {
    let id: Int
    let title: String?
    let content: String?
    let imageUrl: String?
    let source: String?
    let publishedAt: String?
    let category: String?
    let newsUrl: String?

    var meta: String { [source, publishedAt].compactMap { $0 }.joined(separator: " · ") }
}

/// GET /services/weather - every city and district centre of Tajikistan.
struct WeatherResponse: Decodable {
    let cities: [CityWeather]
}

struct CityWeather: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let nameRu: String?
    let region: String
    let current: CurrentWeather
    let hourly: [HourWeather]
    let daily: [DayWeather]

    var title: String { nameRu ?? name }
    var today: DayWeather? { daily.first }
}

struct CurrentWeather: Decodable, Hashable {
    let temp: Int?
    let feelsLike: Int?
    let humidity: Int?
    let wind: Int?
    let pressure: Int?
    let code: Int
    let isDay: Bool
}

struct HourWeather: Decodable, Hashable {
    let time: String
    let temp: Int?
    let code: Int
    let isDay: Bool
    let precip: Int

    /// "2026-10-12T16:00" -> "16:00".
    var label: String { String(time.split(separator: "T").last ?? "") }
}

struct DayWeather: Decodable, Hashable {
    let date: String
    let code: Int
    let max: Int?
    let min: Int?
    let precip: Int
    let sunrise: String?
    let sunset: String?
    let uv: Double?
}

/// Hub cards; articles are pushed as NewsDTO values.
enum ServiceRoute: Hashable {
    case assistant, weather, currency, news
}

// MARK: - Shared loader

/// One copy of the services data for the hub and the detail screens.
@MainActor
@Observable
final class ServicesStore {
    static let shared = ServicesStore()

    var exchange: ExchangeDTO?
    var news: [NewsDTO] = []
    var weather: [CityWeather] = []
    private(set) var cityId = UserDefaults.standard.string(forKey: "safir.weatherCity") ?? "dushanbe"
    private(set) var loading = false
    private(set) var failed = false
    @ObservationIgnored private var loadedAt: Date?

    var city: CityWeather? { weather.first { $0.id == cityId } ?? weather.first }

    func select(city id: String) {
        cityId = id
        UserDefaults.standard.set(id, forKey: "safir.weatherCity")
    }

    /// Cached for 5 minutes; pull-to-refresh forces a reload.
    func load(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        if DemoData.active {
            ServicesDemo.fill(self)
            loadedAt = Date()
            return
        }
        loading = true
        defer { loading = false }
        let api = Session.shared.api
        let rates = try? await api.get("services/exchange", as: ExchangeDTO.self)
        let latest = try? await api.get("services/news", as: [NewsDTO].self)
        let sky = try? await api.get("services/weather", as: WeatherResponse.self)
        withAnimation(Safir.spring) {
            if let rates, !rates.rates.isEmpty { exchange = rates }
            if let latest { news = latest }
            if let sky, !sky.cities.isEmpty { weather = sky.cities }
            failed = rates == nil && latest == nil && sky == nil
        }
        if !failed {
            loadedAt = Date()
            saveWidgetSnapshot()
        }
    }

    /// The home-screen widgets draw this copy (SafirWidgets target).
    private func saveWidgetSnapshot() {
        guard let city else { return }
        let codes = ["USD", "EUR", "RUB"]
        let rates = codes.compactMap { code in exchange?.rates.first { $0.code == code } }
            .map { WidgetSnapshot.Rate(code: $0.code, flag: $0.flag, perUnit: $0.perUnit) }
        WidgetSnapshot(city: city.title, temp: city.current.temp, code: city.current.code, isDay: city.current.isDay,
                       rates: rates, updated: Date().timeIntervalSince1970).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Weather look

/// WMO weather code -> picture, words and sky colours.
enum WeatherKind {
    case clear, partly, cloudy, fog, drizzle, rain, snow, storm

    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partly
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        default: self = .cloudy
        }
    }

    var title: String {
        switch self {
        case .clear: return "Ясно"
        case .partly: return "Переменная облачность"
        case .cloudy: return "Облачно"
        case .fog: return "Туман"
        case .drizzle: return "Морось"
        case .rain: return "Дождь"
        case .snow: return "Снег"
        case .storm: return "Гроза"
        }
    }

    func symbol(day: Bool) -> String {
        switch self {
        case .clear: return day ? "sun.max.fill" : "moon.stars.fill"
        case .partly: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }

    func sky(day: Bool) -> [Color] {
        guard day else {
            return self == .clear || self == .partly
                ? [Color(hex: 0x0B1A3A), Color(hex: 0x2A3F78)]
                : [Color(hex: 0x141D2B), Color(hex: 0x37465A)]
        }
        switch self {
        case .clear: return [Color(hex: 0x2F8FE8), Color(hex: 0x7CC8FF)]
        case .partly: return [Color(hex: 0x4386CF), Color(hex: 0x9CC3E6)]
        case .cloudy: return [Color(hex: 0x62778C), Color(hex: 0xA3B2C2)]
        case .fog: return [Color(hex: 0x7F8C99), Color(hex: 0xC2CAD2)]
        case .drizzle, .rain: return [Color(hex: 0x3E5068), Color(hex: 0x7A8FA6)]
        case .snow: return [Color(hex: 0x7FA6D0), Color(hex: 0xD7E5F3)]
        case .storm: return [Color(hex: 0x252F41), Color(hex: 0x56677F)]
        }
    }
}

// MARK: - Small shared pieces

/// Big cards shrink only a little when pressed.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// `appearIn(_:)` (cards slide up and fade in one after another) lives in Settings/SettingsComponents.swift.
extension View {
    /// iOS 18 zoom transition from a card into its screen; a normal push on iOS 17.
    @ViewBuilder
    func zoomSource(_ id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: ns)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination(_ id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }
}

/// Picture from another site (news photos): plain URLSession, placeholder while loading.
struct RemoteImage: View {
    let url: String?
    /// Off where text sits on top of the placeholder (hero cards).
    var icon = true

    var body: some View {
        if let url = url.flatMap(URL.init(string:)) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().transition(.opacity)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Safir.brandGradient.opacity(0.35)
            if icon {
                Image(systemName: "newspaper.fill").font(.title).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
