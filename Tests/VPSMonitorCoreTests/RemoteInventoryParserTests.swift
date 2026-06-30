import XCTest
@testable import VPSMonitorCore

final class RemoteInventoryParserTests: XCTestCase {
    func testParsesMetricsAndBuildsDirectoryProject() {
        let output = """
        HOST|a2Vlbi1saW1l
        METRIC|cpu_percent|12
        METRIC|memory_used_bytes|1024
        METRIC|memory_total_bytes|4096
        METRIC|disk_free_bytes|8192
        METRIC|disk_total_bytes|16384
        METRIC|uptime_seconds|3600
        DIRECTORY|L29wdC9jbGF1ZGUtYWQtY29ubmVjdG9ycw==
        SERVICE|Y2xhdWRlLWFkLWNvbm5lY3RvcnMuc2VydmljZQ==|Q2xhdWRlIEFkIENvbm5lY3RvcnM=|YWN0aXZl|cnVubmluZw==|L29wdC9jbGF1ZGUtYWQtY29ubmVjdG9ycy9hcHA=|1
        """

        let inventory = RemoteInventoryParser.parse(output)
        let projects = ProjectInventoryBuilder.build(from: inventory)

        XCTAssertEqual(inventory.hostName, "keen-lime")
        XCTAssertEqual(inventory.cpuUsagePercent, 12)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "claude-ad-connectors")
        XCTAssertEqual(projects[0].state, .running)
    }

    func testIncludesStandaloneBotService() {
        let output = """
        SERVICE|dGVsZWdyYW0tYm90LWFwaS5zZXJ2aWNl|VGVsZWdyYW0gQm90IEFQSQ==|YWN0aXZl|cnVubmluZw==||0
        """

        let inventory = RemoteInventoryParser.parse(output)
        let projects = ProjectInventoryBuilder.build(from: inventory)

        XCTAssertEqual(projects.map(\.name), ["telegram-bot-api"])
        XCTAssertEqual(projects[0].state, .running)
    }

    func testLinksRunningProcessToProjectDirectory() {
        let output = """
        DIRECTORY|L29wdC92ay1ib3QtZml0bmVzcw==
        SERVICE|cHJvY2VzczpweXRob24zOjEyMzQ=|UnVubmluZyBwcm9jZXNzOiBweXRob24zIG1haW4ucHk=|YWN0aXZl|cnVubmluZw==|L29wdC92ay1ib3QtZml0bmVzcw==|cHJvY2Vzcw==|0|250|20480
        """

        let inventory = RemoteInventoryParser.parse(output)
        let projects = ProjectInventoryBuilder.build(from: inventory)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "vk-bot-fitness")
        XCTAssertEqual(projects[0].state, .running)
        XCTAssertEqual(projects[0].services.first?.name, "process:python3:1234")
        XCTAssertEqual(projects[0].services.first?.cpuPercent, 2.5)
    }

    func testLinksRunningProcessByCommandLineProjectPath() {
        let output = """
        DIRECTORY|L29wdC92ay1ib3QtZml0bmVzcw==
        SERVICE|cHJvY2VzczpweXRob246NDMyMQ==|UnVubmluZyBwcm9jZXNzOiBweXRob24gL29wdC92ay1ib3QtZml0bmVzcy9tYWluLnB5|YWN0aXZl|cnVubmluZw==|L3Jvb3Q=|cHJvY2Vzcw==|0|120|10240
        """

        let inventory = RemoteInventoryParser.parse(output)
        let projects = ProjectInventoryBuilder.build(from: inventory)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "vk-bot-fitness")
        XCTAssertEqual(projects[0].state, .running)
        XCTAssertEqual(projects[0].services.first?.name, "process:python:4321")
    }
}
