import Foundation

public struct TailscalePeer: Identifiable, Equatable, Sendable {
    public let id: String
    public let hostName: String
    public let dnsName: String?
    public let ipv4: String?
    public let os: String
    public let online: Bool

    public var isAndroid: Bool { os.lowercased() == "android" }

    public init(
        id: String,
        hostName: String,
        dnsName: String? = nil,
        ipv4: String? = nil,
        os: String,
        online: Bool
    ) {
        self.id = id
        self.hostName = hostName
        self.dnsName = dnsName
        self.ipv4 = ipv4
        self.os = os
        self.online = online
    }
}

/// Read-only discovery of Tailscale peers through the installed CLI. Nothing
/// here starts, installs, or configures Tailscale.
public enum TailscaleDiscovery {
    private static let fixedCLIPaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale"
    ]

    public static func locateCLI(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fileManager = FileManager.default
        for path in fixedCLIPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return BinaryLocator.locate("tailscale", environment: environment)
    }

    public static func parseStatus(_ data: Data) throws -> [TailscalePeer] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw MotoMirrorError.parseFailure("Tailscale status is not valid JSON.")
        }

        guard let root = object as? [String: Any] else {
            throw MotoMirrorError.parseFailure("Tailscale status is not a JSON object.")
        }
        guard let rawPeers = root["Peer"] else {
            throw MotoMirrorError.parseFailure("Tailscale status has no Peer dictionary.")
        }
        guard let peersByKey = rawPeers as? [String: Any] else {
            throw MotoMirrorError.parseFailure("Tailscale status Peer is not an object.")
        }

        var peers: [TailscalePeer] = []
        for value in peersByKey.values {
            guard let peer = value as? [String: Any] else { continue }
            guard let id = nonEmptyString(peer["ID"]),
                  let hostName = nonEmptyString(peer["HostName"]) else {
                continue
            }

            peers.append(
                TailscalePeer(
                    id: id,
                    hostName: hostName,
                    dnsName: dnsName(from: peer["DNSName"]),
                    ipv4: firstIPv4(in: peer["TailscaleIPs"]),
                    os: nonEmptyString(peer["OS"]) ?? "",
                    online: peer["Online"] as? Bool ?? false
                )
            )
        }

        return peers
    }

    public static func androidPeers(from peers: [TailscalePeer]) -> [TailscalePeer] {
        peers.filter(\.isAndroid).sorted { lhs, rhs in
            if lhs.online != rhs.online {
                return lhs.online
            }

            let lhsName = lhs.hostName.lowercased()
            let rhsName = rhs.hostName.lowercased()
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            return lhs.id < rhs.id
        }
    }

    public static func isTailscaleIPv4(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host) else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    public static func status(
        using cli: URL,
        runner: ProcessRunner = ProcessRunner()
    ) async throws -> [TailscalePeer] {
        let output = try await runner.run(
            cli,
            arguments: ["status", "--json"],
            timeout: 15
        )
        try output.requireSuccess(cli.lastPathComponent)
        return try parseStatus(Data(output.stdout.utf8))
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dnsName(from value: Any?) -> String? {
        guard var name = nonEmptyString(value) else { return nil }
        if name.hasSuffix(".") {
            name.removeLast()
        }
        return name.isEmpty ? nil : name
    }

    private static func firstIPv4(in value: Any?) -> String? {
        guard let addresses = value as? [String] else { return nil }
        return addresses.first { ipv4Octets($0) != nil }
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let value = Int(part),
                  (0...255).contains(value) else {
                return nil
            }
            octets.append(value)
        }
        return octets
    }
}
