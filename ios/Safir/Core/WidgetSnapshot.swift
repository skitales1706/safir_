import Foundation

/// What the home-screen widgets show (Android SafirWidgets: weather of the chosen city + USD /
/// EUR / RUB). The app writes it into the App Group after loading Services; the widget extension
/// only reads it, so it needs no network, no session and no certificates of its own.
struct WidgetSnapshot: Codable, Equatable {
    struct Rate: Codable, Equatable {
        let code: String
        let flag: String
        let perUnit: Double
    }

    var city: String
    var temp: Int?
    /// WMO weather code.
    var code: Int
    var isDay: Bool
    var rates: [Rate]
    /// Seconds since 1970.
    var updated: Double

    private static let key = "widget_snapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.tj.safir.messenger") }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.key)
    }

    static let placeholder = WidgetSnapshot(
        city: "Душанбе", temp: 21, code: 1, isDay: true,
        rates: [Rate(code: "USD", flag: "🇺🇸", perUnit: 10.93), Rate(code: "EUR", flag: "🇪🇺", perUnit: 11.82),
                Rate(code: "RUB", flag: "🇷🇺", perUnit: 0.135)],
        updated: 0)

    /// SF Symbol for a WMO code (same table as the app's WeatherKind).
    static func symbol(code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
