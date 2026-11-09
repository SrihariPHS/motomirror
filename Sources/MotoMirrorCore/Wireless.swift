import Darwin
import Foundation

/// A validated `host:port` pair for `adb connect`, `adb pair`, and `adb disconnect`.
public struct WirelessAddress: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) throws {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MotoMirrorError.invalidInput("Enter the phone's IP address or hostname.")
        }
        guard (1...65535).contains(port) else {
            throw MotoMirrorError.invalidInput("Port must be between 1 and 65535.")
        }

        self.host = try Self.normalizeHost(trimmed)
        self.port = port
    }

    /// The value adb expects, for example `192.168.1.42:5555` or `[fe80::1]:5555`.
    public var hostPort: String { "\(host):\(port)" }

    private static func normalizeHost(_ host: String) throws -> String {
        if host.hasPrefix("[") {
            guard host.hasSuffix("]"), host.count > 2 else {
                throw MotoMirrorError.invalidInput("The IPv6 address is missing its closing bracket.")
            }
            let inner = String(host.dropFirst().dropLast())
            guard !inner.isEmpty, !inner.contains("["), !inner.contains("]") else {
                throw MotoMirrorError.invalidInput("The IPv6 address is malformed.")
            }
            guard isValidIPv6(inner) else {
                throw MotoMirrorError.invalidInput("\(host) is not a valid IPv6 address.")
            }
            return host
        }

        guard !host.contains(":") else {
            throw MotoMirrorError.invalidInput(
                "IPv6 addresses must be wrapped in brackets, for example [fe80::1]."
            )
        }

        if host.contains("."), host.allSatisfy({ $0 == "." || isASCIIDigit($0) }) {
            let octets = host.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4 else {
                throw MotoMirrorError.invalidInput("\(host) is not a valid IPv4 address.")
            }
            for octet in octets {
                guard !octet.isEmpty, octet.count <= 3,
                      let value = Int(octet), (0...255).contains(value) else {
                    throw MotoMirrorError.invalidInput(
                        "\(host) is not a valid IPv4 address. Each octet must be 0-255."
                    )
                }
            }
            return host
        }

        try validateHostname(host)
        return host
    }

    private static func validateHostname(_ host: String) throws {
        guard host.count <= 253 else {
            throw MotoMirrorError.invalidInput("The hostname is too long.")
        }
        guard host.first != ".", host.last != "." else {
            throw MotoMirrorError.invalidInput("The hostname cannot start or end with a dot.")
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else {
            throw MotoMirrorError.invalidInput("\(host) is not a valid hostname.")
        }

        for label in labels {
            guard !label.isEmpty, label.count <= 63 else {
                throw MotoMirrorError.invalidInput("\(host) is not a valid hostname.")
            }
            guard label.first != "-", label.last != "-" else {
                throw MotoMirrorError.invalidInput("Hostname labels cannot start or end with a hyphen.")
            }
            let allowed = label.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber
                    || character == "-" || character == "_")
            }
            guard allowed else {
                throw MotoMirrorError.invalidInput(
                    "\(host) contains characters that are not allowed in a hostname."
                )
            }
        }
    }

    private static func isValidIPv6(_ literal: String) -> Bool {
        var addressPart = literal
        if let percent = literal.firstIndex(of: "%") {
            addressPart = String(literal[..<percent])
            let zone = String(literal[literal.index(after: percent)...])
            let zoneAllowed = !zone.isEmpty && zone.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber
                    || character == "-" || character == "_" || character == ".")
            }
            guard zoneAllowed else { return false }
        }

        guard !addressPart.isEmpty, addressPart.contains(":") else { return false }

        var address = in6_addr()
        return addressPart.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}

public enum WirelessValidation {
    /// Accepts the 6-digit code Android shows, with optional surrounding spaces
    /// and an optional single space or hyphen between the two groups of three.
    public static func pairingCode(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count == 6, trimmed.allSatisfy(isASCIIDigit) {
            return trimmed
        }

        if trimmed.count == 7 {
            let characters = Array(trimmed)
            let separator = characters[3]
            if separator == " " || separator == "-" {
                let digits = characters[0..<3] + characters[4..<7]
                if digits.allSatisfy(isASCIIDigit) {
                    return String(digits)
                }
            }
        }

        throw MotoMirrorError.invalidInput(
            "Enter the 6-digit pairing code shown on the phone (for example 123456)."
        )
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
