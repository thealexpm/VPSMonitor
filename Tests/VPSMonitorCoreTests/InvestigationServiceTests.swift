import Foundation
import XCTest
@testable import VPSMonitorCore

final class InvestigationServiceTests: XCTestCase {
    func testBuildsIncidentReportWithStoppedServiceAndCommands() {
        let history = [
            MetricSample(timestamp: .now.addingTimeInterval(-180), cpuPercent: 22, memoryPercent: 44, diskUsedPercent: 58, responseMilliseconds: 170),
            MetricSample(timestamp: .now.addingTimeInterval(-120), cpuPercent: 24, memoryPercent: 46, diskUsedPercent: 58, responseMilliseconds: 175),
            MetricSample(timestamp: .now.addingTimeInterval(-60), cpuPercent: 26, memoryPercent: 47, diskUsedPercent: 59, responseMilliseconds: 180),
            MetricSample(timestamp: .now, cpuPercent: 91, memoryPercent: 88, diskUsedPercent: 60, responseMilliseconds: 1350)
        ]

        let lastHealthy = ServerSnapshot(
            hostName: "prod-1",
            checkedAt: .now.addingTimeInterval(-60),
            responseTime: 0.18,
            cpuUsagePercent: 26,
            memoryUsedBytes: 4_000,
            memoryTotalBytes: 10_000,
            diskFreeBytes: 4_000,
            diskTotalBytes: 10_000,
            uptimeSeconds: 2_000,
            projects: [
                DetectedProject(
                    id: "api",
                    name: "api",
                    path: "/opt/api",
                    services: [RemoteService(name: "api.service", description: "", activeState: "active", subState: "running", workingDirectory: "/opt/api", restartCount: 0)],
                    state: .running
                )
            ],
            systemServiceCount: 5
        )

        let current = ServerSnapshot(
            hostName: "prod-1",
            checkedAt: .now,
            responseTime: 1.35,
            cpuUsagePercent: 91,
            memoryUsedBytes: 8_800,
            memoryTotalBytes: 10_000,
            diskFreeBytes: 4_000,
            diskTotalBytes: 10_000,
            uptimeSeconds: 2_400,
            projects: [
                DetectedProject(
                    id: "api",
                    name: "api",
                    path: "/opt/api",
                    services: [RemoteService(name: "api.service", description: "", activeState: "failed", subState: "dead", workingDirectory: "/opt/api", restartCount: 3)],
                    state: .stopped
                )
            ],
            systemServiceCount: 5
        )

        let report = InvestigationService.makeReport(
            snapshot: current,
            history: history,
            lastHealthySnapshot: lastHealthy,
            host: "198.51.100.10",
            user: "deploy"
        )

        XCTAssertFalse(report.stoppedProjects.isEmpty)
        XCTAssertTrue(report.metrics.contains { $0.kind == .response && $0.severity == .high })
        XCTAssertTrue(report.suggestedCommands.contains("ssh 'deploy@198.51.100.10'"))
        XCTAssertTrue(report.suggestedCommands.contains("systemctl status 'api.service' --no-pager"))
        XCTAssertTrue(report.shareText.contains("api"))
        XCTAssertEqual(report.attentionKeys, [
            "metric:cpu",
            "metric:memory",
            "metric:response",
            "project:api"
        ])
        XCTAssertEqual(report.attentionKey, "metric:cpu|metric:memory|metric:response|project:api")
    }

    func testQuotesSuggestedCommands() {
        let current = ServerSnapshot(
            hostName: "quoted-1",
            checkedAt: .now,
            responseTime: 0.2,
            cpuUsagePercent: 25,
            memoryUsedBytes: 4_000,
            memoryTotalBytes: 10_000,
            diskFreeBytes: 4_500,
            diskTotalBytes: 10_000,
            uptimeSeconds: 4_000,
            projects: [
                DetectedProject(
                    id: "bad",
                    name: "bad",
                    path: "/opt/app name/it's-here",
                    services: [RemoteService(name: "bad service.service", description: "", activeState: "failed", subState: "dead", workingDirectory: "/opt/app name", restartCount: 1)],
                    state: .stopped
                )
            ],
            systemServiceCount: 3
        )

        let report = InvestigationService.makeReport(
            snapshot: current,
            history: [],
            lastHealthySnapshot: nil,
            host: "198.51.100.10",
            user: "deploy"
        )

        XCTAssertTrue(report.suggestedCommands.contains("systemctl status 'bad service.service' --no-pager"))
        XCTAssertTrue(report.suggestedCommands.contains("du -sh '/opt/app name/it'\\''s-here'"))
    }

    func testSuggestsProcessCommandsForSyntheticProcessProjects() {
        let current = ServerSnapshot(
            hostName: "process-1",
            checkedAt: .now,
            responseTime: 1.4,
            cpuUsagePercent: 20,
            memoryUsedBytes: 4_000,
            memoryTotalBytes: 10_000,
            diskFreeBytes: 4_500,
            diskTotalBytes: 10_000,
            uptimeSeconds: 4_000,
            projects: [
                DetectedProject(
                    id: "/opt/vk-bot-fitness",
                    name: "vk-bot-fitness",
                    path: "/opt/vk-bot-fitness",
                    services: [RemoteService(name: "process:python:4321", description: "Running process: python /opt/vk-bot-fitness/main.py", activeState: "active", subState: "running", workingDirectory: "/root", fragmentPath: "process", restartCount: 0)],
                    state: .running
                )
            ],
            systemServiceCount: 1
        )

        let report = InvestigationService.makeReport(
            snapshot: current,
            history: [
                MetricSample(timestamp: .now.addingTimeInterval(-60), cpuPercent: 20, memoryPercent: 40, diskUsedPercent: 55, responseMilliseconds: 150)
            ],
            lastHealthySnapshot: current,
            host: "198.51.100.10",
            user: "root"
        )

        XCTAssertTrue(report.suggestedCommands.contains("ps -p 4321 -o pid,ppid,%cpu,%mem,etime,cmd --no-headers"))
        XCTAssertTrue(report.suggestedCommands.contains("readlink -f /proc/4321/cwd"))
        XCTAssertFalse(report.suggestedCommands.contains { $0.contains("systemctl status 'process:") })
    }

    func testStableSlowLatencyIsNotMajorAnomaly() {
        let history = [
            MetricSample(timestamp: .now.addingTimeInterval(-120), cpuPercent: 0, memoryPercent: 26, diskUsedPercent: 25, responseMilliseconds: 2363),
            MetricSample(timestamp: .now.addingTimeInterval(-60), cpuPercent: 0, memoryPercent: 26, diskUsedPercent: 25, responseMilliseconds: 2360),
            MetricSample(timestamp: .now, cpuPercent: 0, memoryPercent: 26, diskUsedPercent: 25, responseMilliseconds: 2355)
        ]

        let current = ServerSnapshot(
            hostName: "sample-node.example.net",
            checkedAt: .now,
            responseTime: 2.355,
            cpuUsagePercent: 0,
            memoryUsedBytes: 535_200_000,
            memoryTotalBytes: 2_060_000_000,
            diskFreeBytes: 23_760_000_000,
            diskTotalBytes: 31_610_000_000,
            uptimeSeconds: 2_000,
            projects: [],
            systemServiceCount: 3
        )

        let report = InvestigationService.makeReport(
            snapshot: current,
            history: history,
            lastHealthySnapshot: current,
            host: "203.0.113.176",
            user: "root"
        )

        XCTAssertFalse(report.needsManualCheck)
        XCTAssertFalse(report.headline.contains("сильн"))
        XCTAssertEqual(report.metrics.first { $0.kind == .response }?.severity, .elevated)
    }

    func testBuildsStableReportWhenMetricsAreNormal() {
        let history = [
            MetricSample(timestamp: .now.addingTimeInterval(-120), cpuPercent: 18, memoryPercent: 40, diskUsedPercent: 55, responseMilliseconds: 150),
            MetricSample(timestamp: .now.addingTimeInterval(-60), cpuPercent: 19, memoryPercent: 42, diskUsedPercent: 55, responseMilliseconds: 145),
            MetricSample(timestamp: .now, cpuPercent: 20, memoryPercent: 41, diskUsedPercent: 55, responseMilliseconds: 155)
        ]

        let current = ServerSnapshot(
            hostName: "stable-1",
            checkedAt: .now,
            responseTime: 0.155,
            cpuUsagePercent: 20,
            memoryUsedBytes: 4_100,
            memoryTotalBytes: 10_000,
            diskFreeBytes: 4_500,
            diskTotalBytes: 10_000,
            uptimeSeconds: 8_000,
            projects: [],
            systemServiceCount: 3
        )

        let report = InvestigationService.makeReport(
            snapshot: current,
            history: history,
            lastHealthySnapshot: current,
            host: "203.0.113.5",
            user: "root"
        )

        XCTAssertEqual(report.metrics.first?.severity, .normal)
        XCTAssertFalse(report.needsManualCheck)
        XCTAssertNil(report.attentionKey)
        XCTAssertTrue(report.headline.contains("стабил") || report.headline.contains("stable"))
    }
}
