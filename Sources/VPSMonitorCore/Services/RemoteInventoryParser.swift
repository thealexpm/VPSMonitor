import Foundation

public struct RemoteInventory: Sendable {
    public var hostName = ""
    public var cpuUsagePercent = 0
    public var memoryUsedBytes: Int64 = 0
    public var memoryTotalBytes: Int64 = 0
    public var diskFreeBytes: Int64 = 0
    public var diskTotalBytes: Int64 = 0
    public var uptimeSeconds = 0
    public var directories: [String] = []
    public var services: [RemoteService] = []

    public init() {}
}

public enum RemoteInventoryParser {
    public static func parse(_ output: String) -> RemoteInventory {
        var inventory = RemoteInventory()

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let kind = fields.first else { continue }

            switch kind {
            case "HOST" where fields.count >= 2:
                inventory.hostName = decode(fields[1])
            case "METRIC" where fields.count >= 3:
                applyMetric(name: fields[1], value: fields[2], to: &inventory)
            case "DIRECTORY" where fields.count >= 2:
                inventory.directories.append(decode(fields[1]))
            case "SERVICE" where fields.count >= 7:
                // Field layout (SERVICE is fields[0]):
                // [1] id  [2] desc  [3] activeState  [4] subState
                // [5] workDir  [6] fragmentPath  [7] restarts
                // [8] cpu×100 (integer)  [9] memKB  (added in later version)
                let hasFragment  = fields.count >= 8
                let fragmentPath = hasFragment ? decode(fields[6]) : ""
                let restartCount = Int(hasFragment ? fields[7] : fields[6]) ?? 0
                let cpuPercent   = fields.count >= 9 ? (Double(fields[8]) ?? 0) / 100.0 : 0
                let memoryBytes  = fields.count >= 10 ? (Int64(fields[9]) ?? 0) * 1024 : 0
                inventory.services.append(
                    RemoteService(
                        name: decode(fields[1]),
                        description: decode(fields[2]),
                        activeState: decode(fields[3]),
                        subState: decode(fields[4]),
                        workingDirectory: decode(fields[5]),
                        fragmentPath: fragmentPath,
                        restartCount: restartCount,
                        cpuPercent: cpuPercent,
                        memoryBytes: memoryBytes
                    )
                )
            default:
                continue
            }
        }

        return inventory
    }

    private static func applyMetric(name: String, value: String, to inventory: inout RemoteInventory) {
        switch name {
        case "cpu_percent":
            inventory.cpuUsagePercent = Int(value) ?? 0
        case "memory_used_bytes":
            inventory.memoryUsedBytes = Int64(value) ?? 0
        case "memory_total_bytes":
            inventory.memoryTotalBytes = Int64(value) ?? 0
        case "disk_free_bytes":
            inventory.diskFreeBytes = Int64(value) ?? 0
        case "disk_total_bytes":
            inventory.diskTotalBytes = Int64(value) ?? 0
        case "uptime_seconds":
            inventory.uptimeSeconds = Int(value) ?? 0
        default:
            break
        }
    }

    private static func decode(_ encoded: String) -> String {
        guard let data = Data(base64Encoded: encoded),
              let value = String(data: data, encoding: .utf8) else {
            return encoded
        }
        return value
    }
}
