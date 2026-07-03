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
    public var vpnStatuses: [VPNStatus] = []
    public var vpnClients: [VPNClient] = []
    public var domainRouteHeader: DomainRoutingSnapshot?
    public var domainWhitelistDomains: [String] = []
    public var domainRouteCandidates: [DomainRouteCandidate] = []

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
            case "VPN" where fields.count >= 8:
                inventory.vpnStatuses.append(
                    VPNStatus(
                        stack: decode(fields[1]),
                        serviceName: decode(fields[2]),
                        activeState: decode(fields[3]),
                        subState: decode(fields[4]),
                        activeConnections: Int(fields[5]) ?? 0,
                        listeningPorts: decode(fields[6])
                            .split(separator: ",")
                            .map(String.init)
                            .filter { !$0.isEmpty },
                        details: decode(fields[7])
                    )
                )
            case "VPNCLIENT" where fields.count >= 14:
                inventory.vpnClients.append(
                    VPNClient(
                        stack: decode(fields[1]),
                        connectionID: decode(fields[2]),
                        identity: decode(fields[3]),
                        publicIP: decode(fields[4]),
                        virtualIP: decode(fields[5]),
                        connectedFor: decode(fields[6]),
                        protocolName: decode(fields[7]),
                        proposal: decode(fields[8]),
                        bytesIn: Int64(fields[9]) ?? 0,
                        bytesOut: Int64(fields[10]) ?? 0,
                        packetsIn: Int(fields[11]) ?? 0,
                        packetsOut: Int(fields[12]) ?? 0,
                        lastActivitySeconds: Int(fields[13])
                    )
                )
            case "DOMAINROUTE" where fields.count >= 6:
                inventory.domainRouteHeader = DomainRoutingSnapshot(
                    dnsServiceState: decode(fields[1]),
                    routeServiceState: decode(fields[2]),
                    whitelistDomains: [],
                    candidateDomains: [],
                    routedIPCount: Int(fields[3]) ?? 0,
                    configPath: decode(fields[4]),
                    logPath: decode(fields[5])
                )
            case "DOMAINWHITELIST" where fields.count >= 2:
                inventory.domainWhitelistDomains.append(decode(fields[1]))
            case "DOMAINCANDIDATE" where fields.count >= 4:
                inventory.domainRouteCandidates.append(
                    DomainRouteCandidate(
                        domain: decode(fields[1]),
                        queryCount: Int(fields[2]) ?? 0,
                        lastSeen: decode(fields[3])
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
