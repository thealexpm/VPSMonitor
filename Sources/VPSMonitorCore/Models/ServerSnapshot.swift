import Foundation

public struct ServerSnapshot: Sendable {
    public let hostName: String
    public let checkedAt: Date
    public let responseTime: TimeInterval
    public let cpuUsagePercent: Int
    public let memoryUsedBytes: Int64
    public let memoryTotalBytes: Int64
    public let diskFreeBytes: Int64
    public let diskTotalBytes: Int64
    public let uptimeSeconds: Int
    public let projects: [DetectedProject]
    public let systemServiceCount: Int
    public let vpn: VPNSnapshot?
    public let domainRouting: DomainRoutingSnapshot?

    public init(
        hostName: String,
        checkedAt: Date,
        responseTime: TimeInterval,
        cpuUsagePercent: Int,
        memoryUsedBytes: Int64,
        memoryTotalBytes: Int64,
        diskFreeBytes: Int64,
        diskTotalBytes: Int64,
        uptimeSeconds: Int,
        projects: [DetectedProject],
        systemServiceCount: Int,
        vpn: VPNSnapshot? = nil,
        domainRouting: DomainRoutingSnapshot? = nil
    ) {
        self.hostName = hostName
        self.checkedAt = checkedAt
        self.responseTime = responseTime
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.uptimeSeconds = uptimeSeconds
        self.projects = projects
        self.systemServiceCount = systemServiceCount
        self.vpn = vpn
        self.domainRouting = domainRouting
    }
}

public struct DomainRoutingSnapshot: Hashable, Sendable {
    public let dnsServiceState: String
    public let routeServiceState: String
    public let whitelistDomains: [String]
    public let candidateDomains: [DomainRouteCandidate]
    public let routedIPCount: Int
    public let configPath: String
    public let logPath: String

    public init(
        dnsServiceState: String,
        routeServiceState: String,
        whitelistDomains: [String],
        candidateDomains: [DomainRouteCandidate],
        routedIPCount: Int,
        configPath: String,
        logPath: String
    ) {
        self.dnsServiceState = dnsServiceState
        self.routeServiceState = routeServiceState
        self.whitelistDomains = whitelistDomains
        self.candidateDomains = candidateDomains
        self.routedIPCount = routedIPCount
        self.configPath = configPath
        self.logPath = logPath
    }

    public var isHealthy: Bool {
        dnsServiceState == "active" && routeServiceState == "active"
    }
}

public struct DomainRouteCandidate: Identifiable, Hashable, Sendable {
    public let domain: String
    public let queryCount: Int
    public let lastSeen: String

    public init(domain: String, queryCount: Int, lastSeen: String) {
        self.domain = domain
        self.queryCount = queryCount
        self.lastSeen = lastSeen
    }

    public var id: String { domain }
}

public struct VPNSnapshot: Hashable, Sendable {
    public let stacks: [VPNStatus]

    public init(stacks: [VPNStatus]) {
        self.stacks = stacks
    }

    public var isHealthy: Bool {
        !stacks.isEmpty && stacks.allSatisfy(\.isHealthy)
    }

    public var totalActiveConnections: Int {
        stacks.reduce(0) { $0 + $1.activeConnections }
    }
}

public struct VPNStatus: Identifiable, Hashable, Sendable {
    public let stack: String
    public let serviceName: String
    public let activeState: String
    public let subState: String
    public let activeConnections: Int
    public let listeningPorts: [String]
    public let details: String
    public let clients: [VPNClient]

    public init(
        stack: String,
        serviceName: String,
        activeState: String,
        subState: String,
        activeConnections: Int,
        listeningPorts: [String],
        details: String,
        clients: [VPNClient] = []
    ) {
        self.stack = stack
        self.serviceName = serviceName
        self.activeState = activeState
        self.subState = subState
        self.activeConnections = activeConnections
        self.listeningPorts = listeningPorts
        self.details = details
        self.clients = clients
    }

    public var id: String { "\(stack)-\(serviceName)" }

    public var isHealthy: Bool {
        activeState == "active" && (subState == "running" || subState == "exited")
    }
}

public struct VPNClient: Identifiable, Hashable, Sendable {
    public let stack: String
    public let connectionID: String
    public let identity: String
    public let publicIP: String
    public let countryCode: String?
    public let virtualIP: String
    public let connectedFor: String
    public let protocolName: String
    public let proposal: String
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let packetsIn: Int
    public let packetsOut: Int
    public let lastActivitySeconds: Int?

    public init(
        stack: String,
        connectionID: String,
        identity: String,
        publicIP: String,
        countryCode: String? = nil,
        virtualIP: String,
        connectedFor: String,
        protocolName: String,
        proposal: String,
        bytesIn: Int64,
        bytesOut: Int64,
        packetsIn: Int,
        packetsOut: Int,
        lastActivitySeconds: Int?
    ) {
        self.stack = stack
        self.connectionID = connectionID
        self.identity = identity
        self.publicIP = publicIP
        self.countryCode = countryCode
        self.virtualIP = virtualIP
        self.connectedFor = connectedFor
        self.protocolName = protocolName
        self.proposal = proposal
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.packetsIn = packetsIn
        self.packetsOut = packetsOut
        self.lastActivitySeconds = lastActivitySeconds
    }

    public var id: String {
        "\(stack)-\(connectionID)-\(publicIP)-\(virtualIP)"
    }

    public func withCountryCode(_ countryCode: String?) -> VPNClient {
        VPNClient(
            stack: stack,
            connectionID: connectionID,
            identity: identity,
            publicIP: publicIP,
            countryCode: countryCode,
            virtualIP: virtualIP,
            connectedFor: connectedFor,
            protocolName: protocolName,
            proposal: proposal,
            bytesIn: bytesIn,
            bytesOut: bytesOut,
            packetsIn: packetsIn,
            packetsOut: packetsOut,
            lastActivitySeconds: lastActivitySeconds
        )
    }
}

public struct DetectedProject: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable {
        case running
        case stopped
        case folderOnly
    }

    public let id: String
    public let name: String
    public let path: String?
    public let services: [RemoteService]
    public let state: State

    public init(id: String, name: String, path: String?, services: [RemoteService], state: State) {
        self.id = id
        self.name = name
        self.path = path
        self.services = services
        self.state = state
    }
}

public struct RemoteService: Hashable, Sendable {
    public let name: String
    public let description: String
    public let activeState: String
    public let subState: String
    public let workingDirectory: String
    public let fragmentPath: String
    public let restartCount: Int
    /// CPU usage averaged since the process started (from `ps %cpu`)
    public let cpuPercent: Double
    /// RSS memory of the main process
    public let memoryBytes: Int64

    public init(
        name: String,
        description: String,
        activeState: String,
        subState: String,
        workingDirectory: String,
        fragmentPath: String = "",
        restartCount: Int,
        cpuPercent: Double = 0,
        memoryBytes: Int64 = 0
    ) {
        self.name = name
        self.description = description
        self.activeState = activeState
        self.subState = subState
        self.workingDirectory = workingDirectory
        self.fragmentPath = fragmentPath
        self.restartCount = restartCount
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    public var isRunning: Bool {
        activeState == "active" && (subState == "running" || subState == "exited")
    }
}

extension DetectedProject {
    /// Sum of CPU% across all services in this project
    public var totalCPUPercent: Double { services.reduce(0) { $0 + $1.cpuPercent } }
    /// Sum of RSS memory across all services in this project
    public var totalMemoryBytes: Int64 { services.reduce(0) { $0 + $1.memoryBytes } }
}
