import Foundation
import Observation

/// App language (Settings → Язык): тоҷикӣ, русский or English - Android's I18n. The Russian text
/// in code is the key; Resources/<lang>.lproj/Localizable.strings hold the rest. Text("литерал")
/// follows it through the locale SafirApp puts in the environment, text in variables through tr().
/// Not tied to the main actor, like ThemeRuntime: views that call tr() redraw on a switch.
@Observable
final class L10n {
    static let shared = L10n()
    static let languages: [(code: String, name: String, english: String)] = [
        ("tg", "Тоҷикӣ", "Tajik"), ("ru", "Русский", "Russian"), ("en", "English", "English"),
    ]

    var lang: String {
        didSet {
            UserDefaults.standard.set(lang, forKey: "safir.lang")
            // System dialogs and permission prompts follow on the next launch.
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
            bundle = Self.bundle(for: lang)
        }
    }

    @ObservationIgnored private var bundle: Bundle?

    private init() {
        let stored = UserDefaults.standard.string(forKey: "safir.lang")
        let phone = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "tg"
        lang = stored ?? (["tg", "ru", "en"].contains(phone) ? phone : "tg")
        // UI tests (ScreenshotTests) tap Russian labels; the CI simulator runs in English.
        if ProcessInfo.processInfo.arguments.contains("-SafirScreenshots") { lang = "ru" }
        bundle = Self.bundle(for: lang)
    }

    var locale: Locale { Locale(identifier: lang == "tg" ? "tg_TJ" : lang) }

    var name: String { Self.languages.first { $0.code == lang }?.name ?? "Тоҷикӣ" }

    func text(_ key: String) -> String {
        guard lang != "ru", let bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func bundle(for lang: String) -> Bundle? {
        Bundle.main.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

/// The text in the chosen language ("Настройки" -> "Танзимот").
func tr(_ key: String) -> String { L10n.shared.text(key) }

/// tr("Через %d мин", 5) - translated format with the arguments filled in.
func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.shared.text(key), locale: L10n.shared.locale, arguments: args)
}
