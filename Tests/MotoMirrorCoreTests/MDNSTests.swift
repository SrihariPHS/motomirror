import XCTest
@testable import MotoMirrorCore

final class MDNSTests: XCTestCase {
    func testParsesPairingAndConnectServices() {
        let output = """
        List of discovered mdns services
        adb-ABC123-xyz\t_adb-tls-pairing._tcp\t192.168.1.42:37123
        adb-ABC123-xyz\t_adb-tls-connect._tcp\t192.168.1.42:5555
        """

        let services = ADBMDNSParser.parse(output)
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].host, "192.168.1.42")
        XCTAssertEqual(services[0].port, 37123)
        XCTAssertEqual(services[0].kind, .pairing)
        XCTAssertEqual(services[1].port, 5555)
        XCTAssertEqual(services[1].kind, .connect)
    }

    func testParsesSpaceSeparatedOutput() {
        let output = """
        adb-1 _adb-tls-pairing._tcp 10.0.0.7:40000
        adb-2 _adb-tls-connect._tcp 10.0.0.7:5555
        """

        let services = ADBMDNSParser.parse(output)
        XCTAssertEqual(services.map(\.host), ["10.0.0.7", "10.0.0.7"])
        XCTAssertEqual(services.map(\.port), [40000, 5555])
    }

    func testParsesBracketedIPv6Address() {
        let output = "adb-v6 _adb-tls-connect._tcp [fe80::1c2d:3e4f]:5555"
        let service = ADBMDNSParser.parse(output).first
        XCTAssertEqual(service?.host, "fe80::1c2d:3e4f")
        XCTAssertEqual(service?.port, 5555)
    }

    func testIgnoresHeaderBlankMalformedAndDuplicateLines() {
        let output = """

        List of discovered mdns services
        not enough fields
        adb-bad _adb-tls-connect._tcp 192.168.1.9:not-a-port
        adb-good _adb-tls-connect._tcp 192.168.1.9:5555
        adb-good _adb-tls-connect._tcp 192.168.1.9:5555

        """

        let services = ADBMDNSParser.parse(output)
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services[0].hostPort, "192.168.1.9:5555")
    }

    func testUnknownServiceTypeIsKept() {
        let output = "adb-x _adb-tls-weird._tcp 192.168.1.9:1234"
        let service = ADBMDNSParser.parse(output).first
        XCTAssertEqual(service?.kind, .unknown)
        XCTAssertEqual(service?.port, 1234)
    }

    func testWirelessEndpointFromIPv4Serial() {
        let endpoint = WirelessEndpoint(serial: "192.168.1.42:5555")
        XCTAssertEqual(endpoint?.host, "192.168.1.42")
        XCTAssertEqual(endpoint?.port, 5555)
        XCTAssertEqual(endpoint?.serial, "192.168.1.42:5555")
    }

    func testWirelessEndpointFromIPv6Serial() {
        let endpoint = WirelessEndpoint(serial: "[fe80::1c2d:3e4f]:5555")
        XCTAssertEqual(endpoint?.host, "fe80::1c2d:3e4f")
        XCTAssertEqual(endpoint?.port, 5555)
    }

    func testWirelessEndpointRejectsInvalidSerial() {
        XCTAssertNil(WirelessEndpoint(serial: ""))
        XCTAssertNil(WirelessEndpoint(serial: "192.168.1.42"))
        XCTAssertNil(WirelessEndpoint(serial: "192.168.1.42:0"))
        XCTAssertNil(WirelessEndpoint(serial: "192.168.1.42:70000"))
        XCTAssertNil(WirelessEndpoint(serial: "fe80::1:5555"))
    }

    func testWirelessEndpointValidatesHostAndPort() {
        XCTAssertThrowsError(try WirelessEndpoint(host: "bad host", port: 5555))
        XCTAssertThrowsError(try WirelessEndpoint(host: "192.168.1.42", port: 0))
        XCTAssertNoThrow(try WirelessEndpoint(host: "192.168.1.42", port: 5555))
    }
}
