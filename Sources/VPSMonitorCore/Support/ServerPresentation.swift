import Foundation

public enum ServerPresentation {
    public struct CountryOption: Identifiable, Hashable, Sendable {
        public let code: String
        public let name: String
        public let englishName: String
        public let russianName: String

        public var id: String { code }
        public var marker: String { ServerPresentation.flagEmoji(for: code) ?? "🌐" }
        public var displayTitle: String { "\(marker) \(name)" }

        public func matches(_ query: String) -> Bool {
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return true }
            return code.lowercased().contains(normalized) ||
                name.lowercased().contains(normalized) ||
                englishName.lowercased().contains(normalized) ||
                russianName.lowercased().contains(normalized)
        }
    }

    public static var countryOptions: [CountryOption] {
        let currentLocale = L10n.locale
        let englishLocale = Locale(identifier: "en_US")
        let russianLocale = Locale(identifier: "ru_RU")

        return Locale.Region.isoRegions.compactMap { region -> CountryOption? in
            let rawCode = region.identifier
            guard let code = normalizedCountryCode(rawCode),
                  let englishName = englishLocale.localizedString(forRegionCode: code) else {
                return nil
            }
            let localizedName = currentLocale.localizedString(forRegionCode: code) ?? englishName
            let russianName = russianLocale.localizedString(forRegionCode: code) ?? englishName
            return CountryOption(
                code: code,
                name: localizedName,
                englishName: englishName,
                russianName: russianName
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func countryOptions(matching query: String) -> [CountryOption] {
        countryOptions.filter { $0.matches(query) }
    }

    public static func countryMarker(for configuration: MonitorConfiguration) -> String {
        if let code = configuration.effectiveCountryCode,
           let marker = flagEmoji(for: code) {
            return marker
        }
        return countryMarker(name: configuration.name, host: configuration.host)
    }

    public static func countryMarker(name: String, host: String) -> String {
        if let code = inferredCountryCode(name: name, host: host),
           let marker = flagEmoji(for: code) {
            return marker
        }
        if isPrivateHost(host) {
            return "🏠"
        }
        return "🌐"
    }

    public static func inferredCountryCode(name: String, host: String) -> String? {
        let searchable = "\(name) \(host)".lowercased()

        if isPrivateHost(host) {
            return nil
        }
        if let code = countryCodeForKnownHost(host) {
            return code
        }
        if containsAny(searchable, ["usa", "us-", "united states", "america", "new-york", "nyc", "ashburn"]) {
            return "US"
        }
        if containsAny(searchable, ["russia", "ru-", "moscow", "msk", "россия", "москва"]) || host.hasSuffix(".ru") {
            return "RU"
        }
        if containsAny(searchable, ["germany", "de-", "frankfurt", "berlin"]) || host.hasSuffix(".de") {
            return "DE"
        }
        if containsAny(searchable, ["france", "fr-", "paris"]) || host.hasSuffix(".fr") {
            return "FR"
        }
        if containsAny(searchable, ["netherlands", "nl-", "amsterdam"]) || host.hasSuffix(".nl") {
            return "NL"
        }
        if containsAny(searchable, ["uk-", "london", "united kingdom", "britain"]) || host.hasSuffix(".uk") {
            return "GB"
        }
        if containsAny(searchable, ["finland", "fi-", "helsinki"]) || host.hasSuffix(".fi") {
            return "FI"
        }
        if containsAny(searchable, ["brazil", "br-", "brasil", "sao-paulo", "saopaulo"]) || host.hasSuffix(".br") {
            return "BR"
        }
        return nil
    }

    public static func normalizedCountryCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 2 else { return nil }
        return normalized
    }

    public static func flagEmoji(for countryCode: String) -> String? {
        guard let code = normalizedCountryCode(countryCode) else { return nil }
        let scalars = code.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            let value = scalar.value
            guard value >= 65, value <= 90 else {
                return nil
            }
            return UnicodeScalar(127397 + Int(value))
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("172.16.")
    }

    private static func countryCodeForKnownHost(_ host: String) -> String? {
        // Local fallback for VPS providers/IPs already observed by this app.
        // This avoids a runtime dependency on an external GeoIP service.
        if host == "79.137.206.86" || host.hasPrefix("79.137.206.") {
            return "FI"
        }
        if host == "194.113.106.176" || host.hasPrefix("194.113.106.") {
            return "RU"
        }
        if host == "186.246.2.237" || host.hasPrefix("186.246.2.") {
            return "RU"
        }
        return nil
    }
}
