import XCTest
@testable import VPSMonitorCore

final class ServerPresentationTests: XCTestCase {
    func testUsesNameHintsForCountryMarker() {
        XCTAssertEqual(ServerPresentation.countryMarker(name: "us-node", host: "203.0.113.10"), "🇺🇸")
        XCTAssertEqual(ServerPresentation.countryMarker(name: "frankfurt-node", host: "203.0.113.10"), "🇩🇪")
    }

    func testUsesDomainHintsForCountryMarker() {
        XCTAssertEqual(ServerPresentation.countryMarker(name: "service", host: "example.ru"), "🇷🇺")
        XCTAssertEqual(ServerPresentation.countryMarker(name: "service", host: "example.fi"), "🇫🇮")
    }

    func testFallsBackToLocalMarkerForPrivateHosts() {
        XCTAssertEqual(ServerPresentation.countryMarker(name: "home-lab", host: "192.168.1.10"), "🏠")
    }

    func testManualCountryOverrideWinsOverDetectedCountry() {
        let configuration = MonitorConfiguration(
            name: "us-node",
            host: "203.0.113.10",
            user: "root",
            refreshInterval: 30,
            countryCode: "US",
            countryCodeOverride: "DE"
        )

        XCTAssertEqual(ServerPresentation.countryMarker(for: configuration), "🇩🇪")
    }

    func testCountrySearchMatchesSpanishAndChineseNames() {
        let spanishMatches = ServerPresentation.countryOptions(matching: "Alemania")
        XCTAssertTrue(spanishMatches.contains { $0.code == "DE" })

        let chineseMatches = ServerPresentation.countryOptions(matching: "德国")
        XCTAssertTrue(chineseMatches.contains { $0.code == "DE" })
    }
}
