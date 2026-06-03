import Foundation

public enum L10n {
    /// Force a specific language for screenshots/testing by setting
    /// `VPSMONITOR_LANG=ru` or `VPSMONITOR_LANG=en` in the launch environment.
    /// Otherwise falls back to the system preferred language.
    public static var isRussian: Bool {
        if let forced = ProcessInfo.processInfo.environment["VPSMONITOR_LANG"]?.lowercased() {
            return forced == "ru"
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let languageCode = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        return languageCode == "ru"
    }

    public static func text(_ russian: String, _ english: String) -> String {
        isRussian ? russian : english
    }
}
