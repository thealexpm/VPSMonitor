import Foundation

/// Fictional but realistic data used for README screenshots and offline previews.
/// Activated when the environment variable `VPSMONITOR_DEMO=1` is set.
/// All IPs are from the documentation range 192.0.2.0/24 (RFC 5737).
public enum DemoData {

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["VPSMONITOR_DEMO"] == "1"
    }

    // MARK: - Demo configurations

    public static let productionServerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    public static let stagingServerID    = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    public static var configurations: [MonitorConfiguration] {
        [
            MonitorConfiguration(
                id: productionServerID,
                name: "production-web",
                host: "192.0.2.10",
                user: "deploy",
                refreshInterval: 30
            ),
            MonitorConfiguration(
                id: stagingServerID,
                name: "staging-bots",
                host: "192.0.2.20",
                user: "root",
                refreshInterval: 30,
                authMethod: .password
            )
        ]
    }

    // MARK: - Demo snapshots

    public static func snapshot(for serverID: UUID) -> ServerSnapshot {
        serverID == productionServerID ? productionSnapshot : stagingSnapshot
    }

    private static let productionSnapshot = ServerSnapshot(
        hostName: "production-web.example.net",
        checkedAt: Date(),
        responseTime: 0.184,
        cpuUsagePercent: 23,
        memoryUsedBytes:  3_220_000_000,
        memoryTotalBytes: 8_000_000_000,
        diskFreeBytes:   42_800_000_000,
        diskTotalBytes: 100_000_000_000,
        uptimeSeconds: 1_584_000,                 // 18 days, 8 hours
        projects: productionProjects,
        systemServiceCount: 0
    )

    private static let stagingSnapshot = ServerSnapshot(
        hostName: "staging-bots.example.net",
        checkedAt: Date(),
        responseTime: 0.267,
        cpuUsagePercent: 9,
        memoryUsedBytes:  1_120_000_000,
        memoryTotalBytes: 4_000_000_000,
        diskFreeBytes:   18_400_000_000,
        diskTotalBytes:  40_000_000_000,
        uptimeSeconds: 642_000,                   // 7 days, 10 hours
        projects: stagingProjects,
        systemServiceCount: 0
    )

    // MARK: - Demo projects

    private static let productionProjects: [DetectedProject] = [
        project(
            path: "/var/www/example.com",
            services: [
                service(name: "nginx.service",
                        cpu: 1.4, memMB: 64,
                        workDir: "/var/www/example.com")
            ]
        ),
        project(
            path: "/opt/payments-api",
            services: [
                service(name: "payments-api.service",
                        cpu: 4.2, memMB: 312,
                        workDir: "/opt/payments-api")
            ]
        ),
        project(
            path: "/opt/postgres",
            services: [
                service(name: "postgresql.service",
                        cpu: 7.8, memMB: 1_240,
                        workDir: "/opt/postgres")
            ]
        ),
        project(
            path: "/opt/redis",
            services: [
                service(name: "redis-server.service",
                        cpu: 0.6, memMB: 96,
                        workDir: "/opt/redis")
            ]
        ),
        project(
            path: "/opt/backups",
            services: []   // folder only
        )
    ]

    private static let stagingProjects: [DetectedProject] = [
        project(
            path: "/opt/telegram-bot",
            services: [
                service(name: "telegram-bot.service",
                        cpu: 2.1, memMB: 184,
                        workDir: "/opt/telegram-bot")
            ]
        ),
        project(
            path: "/opt/wireguard",
            services: [
                service(name: "wg-quick@wg0.service",
                        cpu: 0.3, memMB: 12,
                        workDir: "/opt/wireguard")
            ]
        ),
        project(
            path: "/opt/scraper",
            services: [
                // Stopped service — shows orange warning state
                RemoteService(
                    name: "scraper.service",
                    description: "Web scraper worker",
                    activeState: "inactive",
                    subState: "dead",
                    workingDirectory: "/opt/scraper",
                    fragmentPath: "/etc/systemd/system/scraper.service",
                    restartCount: 3,
                    cpuPercent: 0,
                    memoryBytes: 0
                )
            ]
        )
    ]

    // MARK: - Builder helpers

    private static func project(path: String, services: [RemoteService]) -> DetectedProject {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let state: DetectedProject.State
        if services.contains(where: \.isRunning) { state = .running }
        else if services.isEmpty                 { state = .folderOnly }
        else                                     { state = .stopped }
        return DetectedProject(
            id: path, name: name, path: path, services: services, state: state
        )
    }

    private static func service(
        name: String,
        cpu: Double,
        memMB: Int,
        workDir: String
    ) -> RemoteService {
        RemoteService(
            name: name,
            description: name.replacingOccurrences(of: ".service", with: ""),
            activeState: "active",
            subState: "running",
            workingDirectory: workDir,
            fragmentPath: "/etc/systemd/system/\(name)",
            restartCount: 0,
            cpuPercent: cpu,
            memoryBytes: Int64(memMB) * 1_048_576
        )
    }
}
