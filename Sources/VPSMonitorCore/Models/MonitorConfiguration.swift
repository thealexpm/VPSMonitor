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

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String,
        refreshInterval: TimeInterval,
        authMethod: AuthMethod = .sshKey
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.refreshInterval = refreshInterval
        self.authMethod = authMethod
    }

    public static let placeholder = MonitorConfiguration(
        name: "My VPS",
        host: "your.server.address",
        user: "root",
        refreshInterval: 30
    )
}
