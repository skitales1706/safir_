import Foundation

/// Made-up services data for screenshot mode (-SafirScreenshots), never used with a server.
@MainActor
enum ServicesDemo {
    static let assistantAnswer = """
        С днём рождения! 🎉 Желаю крепкого здоровья, вдохновения в работе и благодарных учеников. \
        Пусть каждый день приносит радость, а все задуманные планы обязательно сбываются!
        """

    static func fill(_ store: ServicesStore) {
        store.exchange = ExchangeDTO(date: "23.10.2026", rates: [
            RateDTO(code: "USD", name: "Доллар США", unit: 1, rate: "10.9384"),
            RateDTO(code: "EUR", name: "Евро", unit: 1, rate: "11.8251"),
            RateDTO(code: "RUB", name: "Российский рубль", unit: 1, rate: "0.1347"),
            RateDTO(code: "CNY", name: "Китайский юань", unit: 1, rate: "1.5312"),
            RateDTO(code: "KZT", name: "Казахстанский тенге", unit: 100, rate: "2.0815"),
            RateDTO(code: "UZS", name: "Узбекский сум", unit: 100, rate: "0.0857"),
            RateDTO(code: "KGS", name: "Кыргызский сом", unit: 1, rate: "0.1251"),
            RateDTO(code: "TRY", name: "Турецкая лира", unit: 1, rate: "0.2612"),
        ])
        store.news = [
            news(1, "Школы Душанбе переходят на электронные дневники", "Образование", "Ховар"),
            news(2, "Нацбанк сохранил ставку рефинансирования на уровне 8%", "Экономика", "Азия-Плюс"),
            news(3, "В Хорогском университете открылся новый IT-центр", "Технологии", "Ховар"),
            news(4, "Сборная Таджикистана вышла в финал турнира CAFA", "Спорт", "Варзиш"),
            news(5, "На Памире выпал первый снег", "Общество", "Азия-Плюс"),
        ]
        store.weather = [
            city("dushanbe", "Душанбе", "dushanbe", code: 0, temp: 24, low: 11, high: 25),
            city("khujand", "Худжанд", "sughd", code: 2, temp: 19, low: 9, high: 21),
            city("khorugh", "Хорог", "gbao", code: 71, temp: 3, low: -4, high: 5),
            city("kulob", "Куляб", "khatlon", code: 61, temp: 17, low: 12, high: 19),
        ]
    }

    private static func news(_ id: Int, _ title: String, _ category: String, _ source: String) -> NewsDTO {
        NewsDTO(id: id, title: title,
                content: "\(title). Подробности будут опубликованы позже. Это демонстрационный текст новости для показа экрана.",
                imageUrl: nil, source: source, publishedAt: "23.10.2026 1\(id):00", category: category, newsUrl: nil)
    }

    private static func city(_ id: String, _ name: String, _ region: String, code: Int, temp: Int, low: Int, high: Int) -> CityWeather {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let hourFormat = DateFormatter()
        hourFormat.locale = Locale(identifier: "en_US_POSIX")
        hourFormat.dateFormat = "yyyy-MM-dd'T'HH:00"
        let now = Date()
        let hours = (0..<24).map { i -> HourWeather in
            let date = now.addingTimeInterval(Double(i) * 3600)
            let hour = Calendar.current.component(.hour, from: date)
            let wave = Int((sin(Double(hour - 9) / 24 * 2 * .pi) * Double(high - low) / 2).rounded())
            return HourWeather(time: hourFormat.string(from: date), temp: (low + high) / 2 + wave,
                               code: i > 14 ? 2 : code, isDay: (7..<19).contains(hour),
                               precip: code >= 61 ? 60 : (i > 16 ? 20 : 0))
        }
        let codes = [code, 1, 2, 3, 61, 0, 0]
        let days = (0..<7).map { i -> DayWeather in
            let d = day.string(from: now.addingTimeInterval(Double(i) * 86_400))
            return DayWeather(date: d, code: codes[i], max: high - i % 3, min: low - i % 2,
                              precip: codes[i] >= 61 ? 70 : i * 5, sunrise: "\(d)T06:41", sunset: "\(d)T17:32", uv: 4)
        }
        return CityWeather(id: id, name: name, nameRu: name, region: region,
                           current: CurrentWeather(temp: temp, feelsLike: temp - 1, humidity: 38, wind: 9, pressure: 1016,
                                                   code: code, isDay: true),
                           hourly: hours, daily: days)
    }
}
