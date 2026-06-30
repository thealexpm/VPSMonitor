import Foundation

public struct MetricSample: Codable, Sendable {
    public let timestamp: Date
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let diskUsedPercent: Double
    public let responseMilliseconds: Double

    public init(
        timestamp: Date,
        cpuPercent: Double,
        memoryPercent: Double,
        diskUsedPercent: Double,
        responseMilliseconds: Double
    ) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskUsedPercent = diskUsedPercent
        self.responseMilliseconds = responseMilliseconds
    }
}
