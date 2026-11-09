import XCTest
@testable import MotoMirrorCore

final class TailscaleDiscoveryTests: XCTestCase {
    private static let statusJSON = #"""
    {
      "Version": "1.78.1",
      "BackendState": "Running",
      "Self": {
        "ID": "self-mac",
        "HostName": "srihari-mac",
        "DNSName": "srihari-mac.tailnet-1234.ts.net.",
        "TailscaleIPs": ["100.64.0.1"],
        "OS": "macOS",
        "Online": true
      },
      "Peer": {
        "nodekey:android-online": {
          "ID": "peer-android-online",
          "HostName": "moto-g85",
          "DNSName": "moto-g85.tailnet-1234.ts.net.",
          "TailscaleIPs": ["fd7a:115c:a1e0::2", "100.101.102.103", "100.101.102.104"],
          "OS": "android",
          "Online": true
        },
        "nodekey:android-offline": {
          "ID": "peer-android-offline",
          "HostName": "pixel-8",
          "DNSName": "pixel-8.tailnet-1234.ts.net.",
          "TailscaleIPs": ["100.90.80.70"],
          "OS": "android",
          "Online": false
        },
        "nodekey:mac": {
          "ID": "peer-mac",
          "HostName": "studio-mac",
          "DNSName": "studio-mac.tailnet-1234.ts.net.",
          "TailscaleIPs": ["100.64.0.20"],
          "OS": "macOS",
          "Online": true
        },
        "nodekey:ipv6-only": {
          "ID": "peer-ipv6",
          "HostName": "ipv6-only",
          "DNSName": "ipv6-only.tailnet-1234.ts.net.",
          "TailscaleIPs": ["fd7a:115c:a1e0::3"],
          "OS": "linux",
          "Online": true
        },
        "nodekey:no-ip": {
          "ID": "peer-no-ip",
          "HostName": "no-ip",
          "OS": "windows",
          "Online": false
        },
        "nodekey:not-a-peer": "malformed",
        "nodekey:missing-id": {
          "HostName": "missing-id",
          "OS": "android",
          "Online": true
        },
        "nodekey:missing-hostname": {
          "ID": "peer-missing-hostname",
          "OS": "android",
          "Online": true
        }
      }
    }
    """#

    // MARK: - Parsing

    func testParseStatusReadsPeersAndChoosesFirstIPv4() throws {
        let peers = try TailscaleDiscovery.parseStatus(Data(Self.statusJSON.utf8))

        XCTAssertEqual(peers.count, 5)
        XCTAssertFalse(peers.contains { $0.id == "self-mac" }, "Self must not be returned as a peer")

        let android = try XCTUnwrap(peers.first { $0.id == "peer-android-online" })
        XCTAssertEqual(android.hostName, "moto-g85")
        XCTAssertEqual(android.dnsName, "moto-g85.tailnet-1234.ts.net")
        XCTAssertEqual(android.ipv4, "100.101.102.103")
        XCTAssertEqual(android.os, "android")
        XCTAssertTrue(android.online)
        XCTAssertTrue(android.isAndroid)

        let offline = try XCTUnwrap(peers.first { $0.id == "peer-android-offline" })
        XCTAssertEqual(offline.ipv4, "100.90.80.70")
        XCTAssertFalse(offline.online)

        let macOS = try XCTUnwrap(peers.first { $0.id == "peer-mac" })
        XCTAssertFalse(macOS.isAndroid)

        let ipv6Only = try XCTUnwrap(peers.first { $0.id == "peer-ipv6" })
        XCTAssertNil(ipv6Only.ipv4)

        let noIP = try XCTUnwrap(peers.first { $0.id == "peer-no-ip" })
        XCTAssertNil(noIP.ipv4)
        XCTAssertNil(noIP.dnsName)
        XCTAssertFalse(noIP.online)
    }

    func testParseStatusIgnoresMalformedPeers() throws {
        let peers = try TailscaleDiscovery.parseStatus(Data(Self.statusJSON.utf8))

        XCTAssertNil(peers.first { $0.hostName == "missing-id" })
        XCTAssertFalse(peers.contains { $0.id == "peer-missing-hostname" })
    }

    func testParseStatusThrowsOnInvalidJSON() {
        XCTAssertThrowsError(try TailscaleDiscovery.parseStatus(Data("not json".utf8))) { error in
            guard case MotoMirrorError.parseFailure = error else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }

    func testParseStatusThrowsWhenPeerDictionaryIsMissing() {
        let data = Data(#"{"Version":"1.78.1","Self":{}}"#.utf8)

        XCTAssertThrowsError(try TailscaleDiscovery.parseStatus(data)) { error in
            guard case MotoMirrorError.parseFailure = error else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }

    // MARK: - Android filtering

    func testAndroidPeersFiltersAndSortsOnlineFirstThenHostName() {
        let peers = [
            peer(id: "offline-zulu", hostName: "Zulu", os: "android", online: false),
            peer(id: "online-beta", hostName: "beta", os: "android", online: true),
            peer(id: "online-alpha", hostName: "Alpha", os: "android", online: true),
            peer(id: "mac", hostName: "Mac", os: "macOS", online: true)
        ]

        let android = TailscaleDiscovery.androidPeers(from: peers)

        XCTAssertEqual(android.map(\.id), ["online-alpha", "online-beta", "offline-zulu"])
    }

    func testAndroidPeersFromFixtureKeepOnlineMotoFirst() throws {
        let peers = try TailscaleDiscovery.parseStatus(Data(Self.statusJSON.utf8))

        XCTAssertEqual(
            TailscaleDiscovery.androidPeers(from: peers).map(\.hostName),
            ["moto-g85", "pixel-8"]
        )
    }

    // MARK: - CIDR

    func testTailscaleIPv4Range() {
        XCTAssertTrue(TailscaleDiscovery.isTailscaleIPv4("100.64.0.1"))
        XCTAssertTrue(TailscaleDiscovery.isTailscaleIPv4("100.127.255.255"))
        XCTAssertFalse(TailscaleDiscovery.isTailscaleIPv4("100.128.0.1"))
        XCTAssertFalse(TailscaleDiscovery.isTailscaleIPv4("99.64.0.1"))
    }

    func testTailscaleIPv4RejectsMalformedAddresses() {
        let malformed = [
            "",
            "100.64.0",
            "100.64.0.1.2",
            "100.64.0.256",
            "100.64.0.-1",
            "100.64.0.a",
            "100.64.0.1 ",
            " 100.64.0.1",
            "100.64.0.1:5555",
            "100.64..1",
            "1000.64.0.1"
        ]

        for host in malformed {
            XCTAssertFalse(
                TailscaleDiscovery.isTailscaleIPv4(host),
                "\(host) should not be a Tailscale IPv4"
            )
        }
    }

    // MARK: - CLI location

    func testLocateCLIPrefersInstalledAppBundle() throws {
        let appPath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        guard FileManager.default.isExecutableFile(atPath: appPath) else {
            throw XCTSkip("Tailscale.app is not installed on this machine")
        }

        XCTAssertEqual(TailscaleDiscovery.locateCLI(environment: [:])?.path, appPath)
    }

    // MARK: - CLI status

    func testStatusRunsCLIWithJSONFlagAndParsesOutput() async throws {
        let fake = try makeFakeCLI(statusJSON: Self.statusJSON)
        defer { fake.cleanup() }

        let peers = try await TailscaleDiscovery.status(using: fake.executable)

        XCTAssertEqual(peers.count, 5)
        XCTAssertEqual(fake.calls, ["[status][--json]"])
        XCTAssertEqual(
            TailscaleDiscovery.androidPeers(from: peers).map(\.hostName),
            ["moto-g85", "pixel-8"]
        )
    }

    func testStatusThrowsWhenCLIExitsNonzero() async throws {
        let fake = try makeFakeCLI(statusJSON: Self.statusJSON, exitStatus: 7)
        defer { fake.cleanup() }

        do {
            _ = try await TailscaleDiscovery.status(using: fake.executable)
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed(let executable, let code, _) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertEqual(executable, "tailscale")
            XCTAssertEqual(code, 7)
        }
        XCTAssertEqual(fake.calls, ["[status][--json]"])
    }

    // MARK: - Helpers

    private func peer(
        id: String,
        hostName: String,
        os: String = "android",
        online: Bool
    ) -> TailscalePeer {
        TailscalePeer(id: id, hostName: hostName, os: os, online: online)
    }

    private struct FakeCLI {
        let directory: URL
        let executable: URL
        let logURL: URL

        var calls: [String] {
            guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
            return text.split(whereSeparator: \.isNewline).map(String.init)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFakeCLI(statusJSON: String, exitStatus: Int32 = 0) throws -> FakeCLI {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("motomirror-tailscale-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let logURL = directory.appendingPathComponent("calls.log")
        try Data().write(to: logURL)

        let fixtureURL = directory.appendingPathComponent("status.json")
        try statusJSON.write(to: fixtureURL, atomically: true, encoding: .utf8)

        let executable = directory.appendingPathComponent("tailscale")
        let script = """
        #!/bin/sh
        for arg in "$@"; do printf '[%s]' "$arg" >> '\(logURL.path)'; done
        printf '\\n' >> '\(logURL.path)'
        case "$*" in
          "status --json") cat '\(fixtureURL.path)'; exit \(exitStatus);;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        return FakeCLI(directory: directory, executable: executable, logURL: logURL)
    }
}
