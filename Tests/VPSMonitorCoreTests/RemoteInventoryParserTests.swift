import XCTest
@testable import VPSMonitorCore

final class RemoteInventoryParserTests: XCTestCase {
    func testParsesMetricsAndBuildsDirectoryProject() {
        let output = """
        HOST|c2FtcGxlLW5vZGU=
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

        XCTAssertEqual(inventory.hostName, "sample-node")
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

    func testParsesVPNStatus() {
        let output = """
        VPN|c3Ryb25nU3dhbg==|c3Ryb25nc3dhbi1zdGFydGVyLnNlcnZpY2U=|YWN0aXZl|cnVubmluZw==|2|NTAwLDQ1MDA=|SUtFdjIvSVBzZWMgc2VydmljZSBkZXRlY3RlZA==
        VPNCLIENT|c3Ryb25nU3dhbg==|aWtldjItZWFwWzZd|dGVzdC11c2Vy|MjAzLjAuMTEzLjc1|MTkyLjAuMi40|MTQgbWludXRlcyBhZ28=|SUtFdjIvSVBzZWM=|QUVTX0NCQ18yNTYvSE1BQ19TSEEyXzI1Nl8xMjg=|377810|3001141|2407|3618|27
        """

        let inventory = RemoteInventoryParser.parse(output)

        XCTAssertEqual(inventory.vpnStatuses.count, 1)
        XCTAssertEqual(inventory.vpnStatuses[0].stack, "strongSwan")
        XCTAssertEqual(inventory.vpnStatuses[0].serviceName, "strongswan-starter.service")
        XCTAssertEqual(inventory.vpnStatuses[0].activeConnections, 2)
        XCTAssertEqual(inventory.vpnStatuses[0].listeningPorts, ["500", "4500"])
        XCTAssertTrue(inventory.vpnStatuses[0].isHealthy)
        XCTAssertEqual(inventory.vpnClients.count, 1)
        XCTAssertEqual(inventory.vpnClients[0].identity, "test-user")
        XCTAssertEqual(inventory.vpnClients[0].publicIP, "203.0.113.75")
        XCTAssertEqual(inventory.vpnClients[0].virtualIP, "192.0.2.4")
        XCTAssertEqual(inventory.vpnClients[0].protocolName, "IKEv2/IPsec")
        XCTAssertEqual(inventory.vpnClients[0].bytesIn, 377810)
        XCTAssertEqual(inventory.vpnClients[0].bytesOut, 3001141)
        XCTAssertEqual(inventory.vpnClients[0].lastActivitySeconds, 27)
    }

    func testParsesDomainRouting() {
        let output = """
        DOMAINROUTE|YWN0aXZl|YWN0aXZl|12|L2V0Yy92cHNtLWRvbWFpbi1yb3V0ZXIvZG9tYWlucy5jb25m|L3Zhci9sb2cvdnBzbS1kb21haW4tcm91dGVyLWRucy5sb2c=
        DOMAINWHITELIST|eWFuZGV4LnJ1
        DOMAINWHITELIST|Z29zdXNsdWdpLnJ1
        DOMAINCANDIDATE|ZXhhbXBsZS5jb20=|7|SnVsIDEgMjE6MDU6MTA=
        """

        let inventory = RemoteInventoryParser.parse(output)

        XCTAssertEqual(inventory.domainRouteHeader?.dnsServiceState, "active")
        XCTAssertEqual(inventory.domainRouteHeader?.routeServiceState, "active")
        XCTAssertEqual(inventory.domainRouteHeader?.routedIPCount, 12)
        XCTAssertEqual(inventory.domainWhitelistDomains, ["yandex.ru", "gosuslugi.ru"])
        XCTAssertEqual(inventory.domainRouteCandidates.count, 1)
        XCTAssertEqual(inventory.domainRouteCandidates[0].domain, "example.com")
        XCTAssertEqual(inventory.domainRouteCandidates[0].queryCount, 7)
        XCTAssertEqual(inventory.domainRouteCandidates[0].lastSeen, "Jul 1 21:05:10")
    }
}
