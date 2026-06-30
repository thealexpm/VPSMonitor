import Foundation
import XCTest
@testable import VPSMonitorCore

final class LocalSSHServerImporterTests: XCTestCase {
    func testImportsSSHHistoryAndKnownHostIPs() throws {
        let home = try makeHomeDirectory()
        try makeSSHDirectory(in: home)
        try """
        : 1772876698:0;ssh testuser@192.168.1.219
        : 1772876699:0;ssh -N -L 18789:127.0.0.1:18789 testuser@203.0.113.10
        : 1772876700:0;ssh git@github.com
        """.write(to: home.appendingPathComponent(".zsh_history"), atomically: true, encoding: .utf8)
        try """
        github.com ssh-ed25519 AAAA
        192.168.1.153 ssh-ed25519 BBBB
        [192.168.1.215]:2222 ssh-ed25519 CCCC
        """.write(to: home.appendingPathComponent(".ssh/known_hosts"), atomically: true, encoding: .utf8)

        let configurations = LocalSSHServerImporter(homeDirectory: home).importConfigurations()
        let byHost = Dictionary(uniqueKeysWithValues: configurations.map { ($0.host, $0) })

        XCTAssertEqual(byHost["192.168.1.219"]?.user, "testuser")
        XCTAssertEqual(byHost["203.0.113.10"]?.user, "testuser")
        XCTAssertEqual(byHost["192.168.1.153"]?.user, "root")
        XCTAssertNil(byHost["192.168.1.215"])
        XCTAssertNil(byHost["github.com"])
    }

    func testImportsSSHConfigAliasesAndIncludes() throws {
        let home = try makeHomeDirectory()
        try makeSSHDirectory(in: home)
        try """
        Include extra_config

        Host prod-vps
          HostName 203.0.113.10
          User deploy

        Host *
          User ignored
        """.write(to: home.appendingPathComponent(".ssh/config"), atomically: true, encoding: .utf8)
        try """
        Host lab-box
          User testuser
        """.write(to: home.appendingPathComponent(".ssh/extra_config"), atomically: true, encoding: .utf8)

        let configurations = LocalSSHServerImporter(homeDirectory: home).importConfigurations()
        let byHost = Dictionary(uniqueKeysWithValues: configurations.map { ($0.host, $0) })

        XCTAssertEqual(byHost["prod-vps"]?.name, "prod-vps")
        XCTAssertEqual(byHost["prod-vps"]?.user, "deploy")
        XCTAssertEqual(byHost["lab-box"]?.user, "testuser")
        XCTAssertNil(byHost["*"])
    }

    func testSkipsHistoryTargetsWithExplicitPorts() throws {
        let home = try makeHomeDirectory()
        try """
        ssh -p 2222 root@198.51.100.12
        scp -P 2200 ./file root@198.51.100.13:/tmp/file
        ssh -o Port=2201 root@198.51.100.15
        ssh root@198.51.100.14
        """.write(to: home.appendingPathComponent(".zsh_history"), atomically: true, encoding: .utf8)

        let configurations = LocalSSHServerImporter(homeDirectory: home).importConfigurations()
        let hosts = Set(configurations.map(\.host))

        XCTAssertEqual(hosts, ["198.51.100.14"])
    }

    private func makeHomeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpsmonitor-importer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSSHDirectory(in home: URL) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".ssh", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}
