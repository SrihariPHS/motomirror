import Foundation

/// Pure parsers for `adb` output. Every parser is tolerant of extra output
/// because adb mixes daemon notices and diagnostics into its stdout.
public enum ADBParser {
    // MARK: - Devices

    public static func parseDevices(_ output: String) -> [AndroidDevice] {
        var devices: [AndroidDevice] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            // Trim spaces only: a leading tab is meaningful in `adb devices` output.
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            guard !line.isEmpty else { continue }
            guard !isNoiseLine(line) else { continue }

            if line.range(of: "no permissions", options: .caseInsensitive) != nil {
                // Typical form:
                // ????????????	no permissions (user in plugdev group; are your udev rules wrong?)
                let candidate: String
                if let tab = line.firstIndex(of: "\t") {
                    candidate = String(line[..<tab]).trimmingCharacters(in: .whitespaces)
                } else {
                    candidate = line.split(whereSeparator: \.isWhitespace)
                        .first
                        .map(String.init) ?? ""
                }
                if !candidate.isEmpty,
                   candidate.range(of: "no permissions", options: .caseInsensitive) == nil {
                    devices.append(AndroidDevice(serial: candidate, state: .unknown))
                }
                continue
            }

            guard let parsed = parseDeviceLine(line) else { continue }
            devices.append(parsed)
        }

        return devices
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("list of devices attached") { return true }
        if lower.hasPrefix("* daemon") { return true }
        if lower.hasPrefix("adb server") { return true }
        if lower.hasPrefix("adb:") { return true }
        if lower.hasPrefix("error:") { return true }
        return false
    }

    private static func parseDeviceLine(_ line: String) -> AndroidDevice? {
        let tabParts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        let serial: String
        let remainder: String

        if tabParts.count == 2 {
            serial = tabParts[0].trimmingCharacters(in: .whitespaces)
            remainder = String(tabParts[1])
        } else {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { return nil }
            serial = String(fields[0])
            remainder = fields.dropFirst().joined(separator: " ")
        }

        guard !serial.isEmpty else { return nil }

        let fields = remainder.split(whereSeparator: \.isWhitespace)
        guard let stateToken = fields.first else { return nil }
        let state = mapState(String(stateToken))

        var model: String?
        var product: String?
        var device: String?
        var hasUSB = false

        for field in fields.dropFirst() {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[field.startIndex..<colon]
            let value = field[field.index(after: colon)...]

            if key == "usb" {
                hasUSB = true
                continue
            }

            guard !value.isEmpty else { continue }
            switch key {
            case "model":
                model = String(value)
            case "product":
                product = String(value)
            case "device":
                device = String(value)
            default:
                break
            }
        }

        let transport: AndroidDevice.Transport
        if serial.contains(":") {
            transport = .wireless
        } else if hasUSB {
            transport = .usb
        } else {
            transport = .unknown
        }

        return AndroidDevice(
            serial: serial,
            state: state,
            model: model,
            product: product,
            device: device,
            transport: transport
        )
    }

    private static func mapState(_ token: String) -> AndroidDevice.State {
        switch token.lowercased() {
        case "device": return .device
        case "offline": return .offline
        case "unauthorized": return .unauthorized
        case "authorizing": return .authorizing
        case "connecting": return .connecting
        default: return .unknown
        }
    }

    // MARK: - Properties

    public static func parseGetProp(_ output: String) -> [String: String] {
        var properties: [String: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), line.hasSuffix("]") else { continue }
            guard let separator = line.range(of: "]: [") else { continue }

            let key = String(line[line.index(after: line.startIndex)..<separator.lowerBound])
            var value = String(line[separator.upperBound...])
            guard value.hasSuffix("]") else { continue }
            value.removeLast()
            guard !key.isEmpty else { continue }

            properties[key] = value
        }

        return properties
    }

    // MARK: - Battery

    public static func parseBattery(_ output: String) -> BatteryInfo? {
        var level: Int?
        var status: String?
        var temperature: Double?
        var voltage: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "level":
                if let value = Int(rawValue), (0...100).contains(value) {
                    level = value
                }
            case "status":
                if let value = Int(rawValue) {
                    status = batteryStatus(value)
                }
            case "temperature":
                if let value = Double(rawValue) {
                    temperature = value / 10.0
                }
            case "voltage":
                if let value = Int(rawValue) {
                    voltage = value
                }
            default:
                break
            }
        }

        guard let level else { return nil }
        return BatteryInfo(
            level: level,
            status: status,
            temperatureCelsius: temperature,
            voltageMillivolts: voltage
        )
    }

    private static func batteryStatus(_ raw: Int) -> String {
        switch raw {
        case 2: return "Charging"
        case 5: return "Full"
        case 3: return "Discharging"
        case 4: return "Not charging"
        case 1: return "Unknown"
        default: return "Unknown"
        }
    }

    // MARK: - Storage

    public static func parseStorage(_ output: String) -> StorageInfo? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.lowercased().hasPrefix("filesystem") { continue }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 6 else { continue }
            guard let mountPoint = tokens.last,
                  mountPoint == "/data" || mountPoint.hasPrefix("/data/") else { continue }

            let blocksIndex = tokens.count - 5
            let availableIndex = tokens.count - 3
            let useIndex = tokens.count - 2

            let useToken = tokens[useIndex]
            guard useToken.hasSuffix("%") || Int64(useToken) != nil else { continue }
            guard let blocks = Int64(tokens[blocksIndex]),
                  let available = Int64(tokens[availableIndex]) else { continue }

            return StorageInfo(
                totalBytes: blocks * 1024,
                availableBytes: available * 1024
            )
        }

        return nil
    }

    // MARK: - Screen

    public static func parseScreen(_ output: String) -> ScreenInfo? {
        var physical: (width: Int, height: Int)?
        var override: (width: Int, height: Int)?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            guard let sizeRange = lower.range(of: "size:") else { continue }

            let rawValue = String(line[sizeRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            guard let dimensions = parseDimensions(rawValue) else { continue }

            if lower.contains("override") {
                override = dimensions
            } else if lower.contains("physical") {
                physical = dimensions
            }
        }

        guard let dimensions = override ?? physical else { return nil }

        return ScreenInfo(
            width: dimensions.width,
            height: dimensions.height,
            density: parseDensity(output)
        )
    }

    public static func parseDensity(_ output: String) -> Int? {
        var physical: Int?
        var override: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            guard lower.contains("density"), let colon = line.firstIndex(of: ":") else { continue }

            let rawValue = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard let value = Int(rawValue), value > 0 else { continue }

            if lower.contains("override") {
                override = value
            } else if lower.contains("physical") {
                physical = value
            }
        }

        return override ?? physical
    }

    private static func parseDimensions(_ raw: String) -> (width: Int, height: Int)? {
        let normalized = raw.replacingOccurrences(of: "X", with: "x")
        let parts = normalized.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let widthText = parts[0].trimmingCharacters(in: .whitespaces)
        let heightText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let width = Int(widthText), let height = Int(heightText),
              width > 0, height > 0 else { return nil }

        return (width, height)
    }
}
