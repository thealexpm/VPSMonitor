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
        systemServiceCount: Int
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
        activeState == "active" && subState == "running"
    }
}

extension DetectedProject {
    /// Sum of CPU% across all services in this project
    public var totalCPUPercent: Double { services.reduce(0) { $0 + $1.cpuPercent } }
    /// Sum of RSS memory across all services in this project
    public var totalMemoryBytes: Int64 { services.reduce(0) { $0 + $1.memoryBytes } }
}
