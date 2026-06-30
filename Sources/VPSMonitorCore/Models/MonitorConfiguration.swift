import Foundation

public enum AuthMethod: Codable, Hashable, Sendable {
    case sshKey
    case password   // actual password stored in Keychain by server ID
}

public struct MonitorConfiguration: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var user: String
    public var refreshInterval: TimeInterval
    public var authMethod: AuthMethod
    /// ISO 3166-1 alpha-2 country code detected for this server.
    public var countryCode: String?
    /// Manual ISO 3166-1 alpha-2 country override chosen by the user.
    public var countryCodeOverride: String?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String,
        refreshInterval: TimeInterval,
        authMethod: AuthMethod = .sshKey,
        countryCode: String? = nil,
        countryCodeOverride: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.refreshInterval = refreshInterval
        self.authMethod = authMethod
        self.countryCode = countryCode
        self.countryCodeOverride = countryCodeOverride
    }

    public var effectiveCountryCode: String? {
        countryCodeOverride ?? countryCode
    }

    public static let placeholder = MonitorConfiguration(
        name: "My VPS",
        host: "your.server.address",
        user: "root",
        refreshInterval: 30
    )
}
