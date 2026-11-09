import XCTest
@testable import MotoMirrorCore

final class WirelessTests: XCTestCase {
    // MARK: - Host and port

    func testAcceptsHostname() throws {
        let address = try WirelessAddress(host: "moto-g85.local", port: 5555)

        XCTAssertEqual(address.host, "moto-g85.local")
        XCTAssertEqual(address.port, 5555)
        XCTAssertEqual(address.hostPort, "moto-g85.local:5555")
    }

    func testTrimsSurroundingWhitespaceFromHost() throws {
        let address = try WirelessAddress(host: " 192.168.1.42 \n", port: 5555)

        XCTAssertEqual(address.host, "192.168.1.42")
        XCTAssertEqual(address.hostPort, "192.168.1.42:5555")
    }

    func testAcceptsIPv4Boundaries() throws {
        XCTAssertEqual(try WirelessAddress(host: "0.0.0.0", port: 1).hostPort, "0.0.0.0:1")
        XCTAssertEqual(
            try WirelessAddress(host: "255.255.255.255", port: 65535).hostPort,
            "255.255.255.255:65535"
        )
    }

    func testRejectsIPv4OctetAbove255() {
        XCTAssertThrowsError(try WirelessAddress(host: "192.168.1.256", port: 5555)) { error in
            guard case MotoMirrorError.invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
        XCTAssertThrowsError(try WirelessAddress(host: "999.1.1.1", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: "192.168.1", port: 5555))
    }

    func testRejectsEmptyHost() {
        XCTAssertThrowsError(try WirelessAddress(host: "", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: "   ", port: 5555))
    }

    func testRejectsShellMetacharactersAndWhitespace() {
        let badHosts = [
            "192.168.1.42; reboot",
            "$(whoami)",
            "`id`",
            "host name",
            "host\tname",
            "host|cat",
            "host&background",
            "host>file"
        ]

        for host in badHosts {
            XCTAssertThrowsError(try WirelessAddress(host: host, port: 5555), host) { error in
                guard case MotoMirrorError.invalidInput = error else {
                    return XCTFail("expected invalidInput for \(host), got \(error)")
                }
            }
        }
    }

    func testRejectsInvalidHostnames() {
        XCTAssertThrowsError(try WirelessAddress(host: "-bad.local", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: "bad-.local", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: "bad..local", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: ".bad.local", port: 5555))
    }

    func testAcceptsBracketedIPv6Literal() throws {
        let loopback = try WirelessAddress(host: "[::1]", port: 5555)
        XCTAssertEqual(loopback.host, "[::1]")
        XCTAssertEqual(loopback.hostPort, "[::1]:5555")

        let scoped = try WirelessAddress(host: "[fe80::1%en0]", port: 5555)
        XCTAssertEqual(scoped.hostPort, "[fe80::1%en0]:5555")
    }

    func testRejectsUnbracketedOrInvalidIPv6() {
        XCTAssertThrowsError(try WirelessAddress(host: "::1", port: 5555)) { error in
            guard case MotoMirrorError.invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
        XCTAssertThrowsError(try WirelessAddress(host: "[gggg::1]", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: "[::1", port: 5555))
        XCTAssertThrowsError(try WirelessAddress(host: "[]", port: 5555))
    }

    func testRejectsPortsOutsideRange() {
        XCTAssertThrowsError(try WirelessAddress(host: "192.168.1.42", port: 0))
        XCTAssertThrowsError(try WirelessAddress(host: "192.168.1.42", port: -1))
        XCTAssertThrowsError(try WirelessAddress(host: "192.168.1.42", port: 65536))
    }

    func testAddressEquality() throws {
        XCTAssertEqual(
            try WirelessAddress(host: " 192.168.1.42 ", port: 5555),
            try WirelessAddress(host: "192.168.1.42", port: 5555)
        )
    }

    // MARK: - Pairing code

    func testAcceptsPlainSixDigitCode() throws {
        XCTAssertEqual(try WirelessValidation.pairingCode("123456"), "123456")
    }

    func testAcceptsSurroundingWhitespace() throws {
        XCTAssertEqual(try WirelessValidation.pairingCode(" 123456 "), "123456")
        XCTAssertEqual(try WirelessValidation.pairingCode("\t123456\n"), "123456")
    }

    func testAcceptsSingleSpaceOrHyphenInTheMiddle() throws {
        XCTAssertEqual(try WirelessValidation.pairingCode("123 456"), "123456")
        XCTAssertEqual(try WirelessValidation.pairingCode("123-456"), "123456")
        XCTAssertEqual(try WirelessValidation.pairingCode(" 123-456 "), "123456")
        XCTAssertEqual(try WirelessValidation.pairingCode(" 123 456 "), "123456")
    }

    func testRejectsInvalidPairingCodes() {
        let badCodes = [
            "",
            "12345",
            "1234567",
            "1234-56",
            "12-3456",
            "123--456",
            "123  456",
            "123a56",
            "abcdef",
            "123_456"
        ]

        for code in badCodes {
            XCTAssertThrowsError(try WirelessValidation.pairingCode(code), "\(code)") { error in
                guard case MotoMirrorError.invalidInput = error else {
                    return XCTFail("expected invalidInput for \(code), got \(error)")
                }
            }
        }
    }
}
