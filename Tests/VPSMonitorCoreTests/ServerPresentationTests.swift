import XCTest
@testable import VPSMonitorCore

final class ServerPresentationTests: XCTestCase {
    func testUsesNameHintsForCountryMarker() {
        XCTAssertEqual(ServerPresentation.countryMarker(name: "usa-vpn", host: "193.233.131.167"), "🇺🇸")
        XCTAssertEqual(ServerPresentation.countryMarker(name: "frankfurt-node", host: "203.0.113.10"), "🇩🇪")
    }

    func testUsesKnownObservedIPPrefixes() {
        XCTAssertEqual(ServerPresentation.countryMarker(name: "keen-lime", host: "79.137.206.86"), "🇫🇮")
        XCTAssertEqual(ServerPresentation.countryMarker(name: "handsome-azure", host: "194.113.106.176"), "🇷🇺")
        XCTAssertEqual(ServerPresentation.countryMarker(name: "Younica", host: "186.246.2.237"), "🇷🇺")
    }

    func testFallsBackToLocalMarkerForPrivateHosts() {
        XCTAssertEqual(ServerPresentation.countryMarker(name: "home-lab", host: "192.168.1.10"), "🏠")
    }

    func testManualCountryOverrideWinsOverDetectedCountry() {
        let configuration = MonitorConfiguration(
            name: "usa-vpn",
            host: "193.233.131.167",
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
