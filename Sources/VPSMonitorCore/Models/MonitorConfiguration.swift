import Foundation

public struct MonitorConfiguration: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var user: String
    public var refreshInterval: TimeInterval

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String,
        refreshInterval: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.refreshInterval = refreshInterval
    }

    public static let placeholder = MonitorConfiguration(
        name: "My VPS",
        host: "your.server.address",
        user: "root",
        refreshInterval: 30
    )
}
