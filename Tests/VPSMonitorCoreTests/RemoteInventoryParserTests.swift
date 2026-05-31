import Testing
@testable import VPSMonitorCore

struct RemoteInventoryParserTests {
    @Test
    func parsesMetricsAndBuildsDirectoryProject() {
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

        #expect(inventory.hostName == "keen-lime")
        #expect(inventory.cpuUsagePercent == 12)
        #expect(projects.count == 1)
        #expect(projects[0].name == "claude-ad-connectors")
        #expect(projects[0].state == .running)
    }

    @Test
    func includesStandaloneBotService() {
        let output = """
        SERVICE|dGVsZWdyYW0tYm90LWFwaS5zZXJ2aWNl|VGVsZWdyYW0gQm90IEFQSQ==|YWN0aXZl|cnVubmluZw==||0
        """

        let inventory = RemoteInventoryParser.parse(output)
        let projects = ProjectInventoryBuilder.build(from: inventory)

        #expect(projects.map(\.name) == ["telegram-bot-api"])
        #expect(projects[0].state == .running)
    }
}
