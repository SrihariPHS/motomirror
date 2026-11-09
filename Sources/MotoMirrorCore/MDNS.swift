import Foundation

public struct ADBMDNSService: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case pairing
        case connect
        case unknown
    }

    public let name: String
    public let type: String
    public let host: String
    public let port: Int

    public var id: String { "\(name)|\(type)|\(host):\(port)" }
    public var hostPort: String { "\(host):\(port)" }
    public var kind: Kind {
        if type.contains("pairing") { return .pairing }
        if type.contains("connect") { return .connect }
        return .unknown
    }

    public init(name: String, type: String, host: String, port: Int) {
        self.name = name
        self.type = type
        self.host = host
        self.port = port
    }
}

public enum ADBMDNSParser {
    public static func parse(_ output: String) -> [ADBMDNSService] {
        var services: [ADBMDNSService] = []
        var seen = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !line.lowercased().hasPrefix("list of discovered") else { continue }

            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3 else { continue }

            guard let type = fields.first(where: { $0.contains("_adb-tls-") }),
                  let address = fields.last,
                  let endpoint = parseAddress(address)
            else {
                continue
            }

            let name = fields.first ?? "adb"
            let service = ADBMDNSService(
                name: name,
                type: type,
                host: endpoint.host,
                port: endpoint.port
            )
            guard seen.insert(service.id).inserted else { continue }
            services.append(service)
        }

        return services
    }

    private static func parseAddress(_ raw: String) -> (host: String, port: Int)? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("["),
           let closing = value.firstIndex(of: "]") {
            let host = String(value[value.index(after: value.startIndex)..<closing])
            let remainder = value[value.index(after: closing)...]
            guard remainder.hasPrefix(":"),
                  let port = Int(remainder.dropFirst()),
                  (1...65535).contains(port),
                  !host.isEmpty
            else {
                return nil
            }
            return (host, port)
        }

        guard let colon = value.lastIndex(of: ":") else { return nil }
        let host = String(value[..<colon])
        let portText = String(value[value.index(after: colon)...])
        guard !host.isEmpty,
              !host.contains(":"),
              let port = Int(portText),
              (1...65535).contains(port)
        else {
            return nil
        }
        return (host, port)
    }
}

public struct WirelessEndpoint: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) throws {
        let address = try WirelessAddress(host: host, port: port)
        self.host = address.host
        self.port = address.port
    }

    public init?(serial: String) {
        let value = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("["),
           let closing = value.firstIndex(of: "]") {
            let host = String(value[value.index(after: value.startIndex)..<closing])
            let remainder = value[value.index(after: closing)...]
            guard remainder.hasPrefix(":"),
                  let port = Int(remainder.dropFirst()),
                  (1...65535).contains(port)
            else {
                return nil
            }
            self.host = host
            self.port = port
            return
        }

        guard let colon = value.lastIndex(of: ":") else { return nil }
        let host = String(value[..<colon])
        guard !host.isEmpty,
              !host.contains(":"),
              let port = Int(value[value.index(after: colon)...]),
              (1...65535).contains(port)
        else {
            return nil
        }
        self.host = host
        self.port = port
    }

    public var serial: String { "\(host):\(port)" }
}
