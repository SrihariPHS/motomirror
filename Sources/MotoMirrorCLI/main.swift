import Darwin
import Foundation
import MotoMirrorCore

// motomirrorctl — headless CLI used by the MotoMirror verification harness.
// Hand-rolled argument parsing only: no third-party packages.

let motomirrorCLIVersion = "1.0.0"

// MARK: - Errors and output

enum CLIError: Error {
    case usage(String)
    case failure(String)

    var exitCode: Int32 {
        switch self {
        case .usage: return 2
        case .failure: return 1
        }
    }

    var message: String {
        switch self {
        case .usage(let text), .failure(let text): return text
        }
    }
}

func writeStandardError(_ text: String) {
    guard let data = (text + "\n").data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
}

func writeStandardOutput(_ text: String) {
    guard let data = (text + "\n").data(using: .utf8) else { return }
    FileHandle.standardOutput.write(data)
}

func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw CLIError.failure("Could not encode JSON output.")
    }
    return string
}

func expandedPath(_ raw: String) -> String {
    (raw as NSString).expandingTildeInPath
}

func fileSize(_ path: String) -> Int64 {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber else {
        return 0
    }
    return size.int64Value
}

func ensureParentDirectory(for path: String) throws {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()
    guard !directory.path.isEmpty else { return }
    do {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    } catch {
        throw CLIError.failure("Could not create directory \(directory.path): \(error.localizedDescription)")
    }
}

// MARK: - Argument parsing

struct CommandOptions {
    var flags: Set<String> = []
    var values: [String: String] = [:]
    var positionals: [String] = []

    init(_ arguments: [String], valueOptions: Set<String> = [], flagOptions: Set<String> = []) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                positionals.append(contentsOf: arguments.dropFirst(index + 1))
                break
            }
            guard argument.hasPrefix("--") || argument.hasPrefix("-") else {
                positionals.append(argument)
                index += 1
                continue
            }

            var name = argument.hasPrefix("--") ? String(argument.dropFirst(2)) : String(argument.dropFirst(1))
            var inlineValue: String?
            if let separator = name.firstIndex(of: "=") {
                inlineValue = String(name[name.index(after: separator)...])
                name = String(name[..<separator])
            }

            if flagOptions.contains(name) {
                guard inlineValue == nil else {
                    throw CLIError.usage("Option --\(name) does not take a value.")
                }
                flags.insert(name)
            } else if valueOptions.contains(name) {
                if let inlineValue {
                    values[name] = inlineValue
                } else {
                    guard index + 1 < arguments.count else {
                        throw CLIError.usage("Option --\(name) requires a value.")
                    }
                    index += 1
                    values[name] = arguments[index]
                }
            } else {
                throw CLIError.usage("Unknown option --\(name). Run motomirrorctl help for usage.")
            }
            index += 1
        }
    }

    func required(_ name: String) throws -> String {
        guard let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            throw CLIError.usage("Missing required option --\(name).")
        }
        return value
    }

    func string(_ name: String) -> String? {
        guard let value = values[name] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func integer(_ name: String, default defaultValue: Int) throws -> Int {
        guard let raw = string(name) else { return defaultValue }
        guard let value = Int(raw) else {
            throw CLIError.usage("Option --\(name) must be an integer.")
        }
        return value
    }

    func optionalInteger(_ name: String) throws -> Int? {
        guard let raw = string(name) else { return nil }
        guard let value = Int(raw) else {
            throw CLIError.usage("Option --\(name) must be an integer.")
        }
        return value
    }

    func double(_ name: String, default defaultValue: Double) throws -> Double {
        guard let raw = string(name) else { return defaultValue }
        guard let value = Double(raw), value.isFinite else {
            throw CLIError.usage("Option --\(name) must be a number.")
        }
        return value
    }

    func port(_ name: String, default defaultValue: Int) throws -> Int {
        let value = try integer(name, default: defaultValue)
        guard (1...65535).contains(value) else {
            throw CLIError.usage("Port must be between 1 and 65535.")
        }
        return value
    }

    func requiredPort(_ name: String) throws -> Int {
        let raw = try required(name)
        guard let value = Int(raw), (1...65535).contains(value) else {
            throw CLIError.usage("Option --\(name) must be a port between 1 and 65535.")
        }
        return value
    }
}

// MARK: - Tool discovery

enum ToolLocator {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func locate(_ name: String, overrideKey: String) -> URL? {
        if let override = environment[overrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: expanded) else {
                return nil
            }
            return URL(fileURLWithPath: expanded)
        }
        return BinaryLocator.locate(name)
    }

    static func adb() -> URL? { locate("adb", overrideKey: "MOTOMIRROR_ADB") }
    static func scrcpy() -> URL? { locate("scrcpy", overrideKey: "MOTOMIRROR_SCRCPY") }
    static func ffmpeg() -> URL? { locate("ffmpeg", overrideKey: "MOTOMIRROR_FFMPEG") }

    static func requireADB() throws -> URL {
        guard let adb = adb() else {
            throw CLIError.failure(
                "adb was not found. Set MOTOMIRROR_ADB or install Android platform-tools."
            )
        }
        return adb
    }

    static func requireToolchain() throws -> Toolchain {
        guard let adb = adb() else {
            throw CLIError.failure(
                "adb was not found. Set MOTOMIRROR_ADB or install Android platform-tools."
            )
        }
        guard let scrcpy = scrcpy() else {
            throw CLIError.failure(
                "scrcpy was not found. Set MOTOMIRROR_SCRCPY or install scrcpy 5.0.1."
            )
        }
        return Toolchain(adb: adb, scrcpy: scrcpy, ffmpeg: ffmpeg())
    }
}

func makeADBClient(adbURL: URL) -> any ADBServicing {
    ADBClient(adbURL: adbURL, runner: ProcessRunner())
}

func toolVersion(executable: URL, arguments: [String], timeout: TimeInterval = 20) async -> String? {
    let runner = ProcessRunner()
    guard let output = try? await runner.run(executable, arguments: arguments, timeout: timeout) else {
        return nil
    }
    let text = output.stdout.isEmpty ? output.stderr : output.stdout
    return text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .first
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - JSON payloads

struct DoctorPayload: Encodable {
    let adb: String?
    let scrcpy: String?
    let ffmpeg: String?
    let adbVersion: String?
    let scrcpyVersion: String?
    let deviceCount: Int
    let ok: Bool

    enum CodingKeys: String, CodingKey {
        case adb, scrcpy, ffmpeg, adbVersion, scrcpyVersion, deviceCount, ok
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode optionals explicitly so missing tools appear as JSON null
        // instead of disappearing from the object.
        try container.encode(adb, forKey: .adb)
        try container.encode(scrcpy, forKey: .scrcpy)
        try container.encode(ffmpeg, forKey: .ffmpeg)
        try container.encode(adbVersion, forKey: .adbVersion)
        try container.encode(scrcpyVersion, forKey: .scrcpyVersion)
        try container.encode(deviceCount, forKey: .deviceCount)
        try container.encode(ok, forKey: .ok)
    }
}

struct MDNSServicePayload: Encodable {
    let name: String
    let type: String
    let kind: String
    let host: String
    let port: Int
    let hostPort: String

    init(_ service: ADBMDNSService) {
        name = service.name
        type = service.type
        kind = service.kind.rawValue
        host = service.host
        port = service.port
        hostPort = service.hostPort
    }
}

struct DevicePayload: Encodable {
    let serial: String
    let state: String
    let model: String?
    let transport: String
    let displayName: String

    init(_ device: AndroidDevice) {
        serial = device.serial
        state = device.state.rawValue
        model = device.model
        transport = device.transport.rawValue
        displayName = device.displayName
    }

    enum CodingKeys: String, CodingKey {
        case serial, state, model, transport, displayName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serial, forKey: .serial)
        try container.encode(state, forKey: .state)
        try container.encode(model, forKey: .model)
        try container.encode(transport, forKey: .transport)
        try container.encode(displayName, forKey: .displayName)
    }
}

struct BatteryPayload: Encodable {
    let level: Int?
    let status: String?
    let temperatureCelsius: Double?
    let voltageMillivolts: Int?
    let isCharging: Bool

    init(_ battery: BatteryInfo?) {
        level = battery?.level
        status = battery?.status
        temperatureCelsius = battery?.temperatureCelsius
        voltageMillivolts = battery?.voltageMillivolts
        isCharging = battery?.isCharging ?? false
    }
}

struct StoragePayload: Encodable {
    let totalBytes: Int64
    let availableBytes: Int64
    let usedBytes: Int64
    let usedFraction: Double

    init(_ storage: StorageInfo?) {
        totalBytes = storage?.totalBytes ?? 0
        availableBytes = storage?.availableBytes ?? 0
        usedBytes = storage?.usedBytes ?? 0
        usedFraction = storage?.usedFraction ?? 0
    }
}

struct ScreenPayload: Encodable {
    let width: Int
    let height: Int
    let density: Int?

    init(_ screen: ScreenInfo?) {
        width = screen?.width ?? 0
        height = screen?.height ?? 0
        density = screen?.density
    }
}

struct TailscalePeerPayload: Encodable {
    let id: String
    let hostName: String
    let dnsName: String?
    let ipv4: String?
    let os: String
    let online: Bool
    let isAndroid: Bool

    enum CodingKeys: String, CodingKey {
        case id, hostName, dnsName, ipv4, os, online, isAndroid
    }

    init(_ peer: TailscalePeer) {
        id = peer.id
        hostName = peer.hostName
        dnsName = peer.dnsName
        ipv4 = peer.ipv4
        os = peer.os
        online = peer.online
        isAndroid = peer.isAndroid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostName, forKey: .hostName)
        try container.encode(dnsName, forKey: .dnsName)
        try container.encode(ipv4, forKey: .ipv4)
        try container.encode(os, forKey: .os)
        try container.encode(online, forKey: .online)
        try container.encode(isAndroid, forKey: .isAndroid)
    }
}

struct InfoPayload: Encodable {
    let serial: String
    let manufacturer: String?
    let model: String?
    let androidVersion: String?
    let sdk: String?
    let abi: String?
    let battery: BatteryPayload
    let storage: StoragePayload
    let screen: ScreenPayload

    init(_ details: DeviceDetails) {
        serial = details.serial
        manufacturer = details.manufacturer
        model = details.model
        androidVersion = details.androidVersion
        sdk = details.sdk
        abi = details.abi
        battery = BatteryPayload(details.battery)
        storage = StoragePayload(details.storage)
        screen = ScreenPayload(details.screen)
    }
}

// MARK: - Commands

enum CLI {
    static func makeToolbox() throws -> AgentToolbox {
        let adb = try ToolLocator.requireADB()
        return AgentToolbox(adbURL: adb, scrcpyURL: ToolLocator.scrcpy())
    }

    static let usageText = """
    motomirrorctl \(motomirrorCLIVersion) — headless MotoMirror controller

    USAGE:
      motomirrorctl doctor [--json]
      motomirrorctl devices [--json]
      motomirrorctl info --serial SERIAL [--json]
      motomirrorctl screenshot --serial SERIAL --out PATH
      motomirrorctl mirror --serial SERIAL [options]
      motomirrorctl wireless discover [--json]
      motomirrorctl wireless pair --host HOST --port PORT --code CODE
      motomirrorctl wireless connect --host HOST --port PORT
      motomirrorctl wireless disconnect --host HOST --port PORT
      motomirrorctl wireless tcpip --serial SERIAL [--port PORT]
      motomirrorctl tailscale peers [--json]
      motomirrorctl tailscale status [--json]
      motomirrorctl apps list|current|launch|stop|install|uninstall [--serial S] [--json]
      motomirrorctl ui dump|find|tap|text|key|swipe [--serial S] [--json]
      motomirrorctl open URL [--serial S]
      motomirrorctl files push|pull|ls [--serial S] [--json]
      motomirrorctl shell COMMAND [--serial S]
      motomirrorctl screen wake|sleep|rotate N [--serial S]
      motomirrorctl volume get|set N [--serial S]
      motomirrorctl logcat [-n N] [--serial S]
      motomirrorctl wait-for app PACKAGE|device [--serial S] [--timeout SEC]
      motomirrorctl agent tools [--json]
      motomirrorctl agent call TOOL --args JSON [--json]
      motomirrorctl mcp
      motomirrorctl version
      motomirrorctl help

    MIRROR OPTIONS:
      --duration SECONDS   Run for N seconds (0 or omitted = until interrupted)
      --record PATH        Record an MP4 file
      --no-audio           Disable audio forwarding
      --max-size N         Limit the longest screen edge
      --max-fps N          Limit capture frame rate
      --bitrate MBPS       Video bit rate in megabits per second
      --headless           Add --no-window and --no-playback
      --no-window          Add --no-window only

    ENVIRONMENT:
      MOTOMIRROR_ADB, MOTOMIRROR_SCRCPY, MOTOMIRROR_FFMPEG override tool paths.
    """

    static func run(_ arguments: [String]) async throws -> Int32 {
        var arguments = arguments
        let usbOnly = arguments.contains("--usb")
            || ProcessInfo.processInfo.environment["MOTOMIRROR_TRANSPORT"]?.lowercased() == "usb"
        arguments.removeAll { $0 == "--usb" }
        var globalSerial: String?
        if let index = arguments.firstIndex(of: "--serial"), index + 1 < arguments.count {
            globalSerial = arguments[index + 1]
            arguments.removeSubrange(index...index + 1)
        }
        guard let command = arguments.first else {
            writeStandardError(usageText)
            return 2
        }
        var rest = Array(arguments.dropFirst())
        let serialCommands: Set<String> = [
            "info", "screenshot", "mirror", "apps", "ui", "open", "files",
            "shell", "screen", "volume", "logcat", "wait-for"
        ]
        if serialCommands.contains(command) {
            if usbOnly { rest.append("--usb") }
            if let globalSerial { rest.append(contentsOf: ["--serial", globalSerial]) }
        }

        switch command {
        case "apps":
            return try await AgentCLI.apps(rest, toolbox: makeToolbox())
        case "ui":
            return try await AgentCLI.ui(rest, toolbox: makeToolbox())
        case "files":
            return try await AgentCLI.files(rest, toolbox: makeToolbox())
        case "open":
            return try await AgentCLI.open(rest, toolbox: makeToolbox())
        case "shell":
            return try await AgentCLI.shell(rest, toolbox: makeToolbox())
        case "screen":
            return try await AgentCLI.screen(rest, toolbox: makeToolbox())
        case "volume":
            return try await AgentCLI.volume(rest, toolbox: makeToolbox())
        case "logcat":
            return try await AgentCLI.logcat(rest, toolbox: makeToolbox())
        case "wait-for":
            return try await AgentCLI.waitFor(rest, toolbox: makeToolbox())
        case "agent":
            return try await AgentCLI.agents(rest, toolbox: makeToolbox())
        case "mcp":
            return try await MCP.run(toolbox: makeToolbox())
        case "doctor":
            return try await doctor(rest)
        case "devices":
            return try await devices(rest)
        case "info":
            return try await info(rest)
        case "screenshot":
            return try await screenshot(rest)
        case "mirror":
            return try await mirror(rest)
        case "wireless":
            return try await wireless(rest)
        case "tailscale":
            return try await tailscale(rest)
        case "version", "--version", "-v":
            writeStandardOutput("motomirrorctl \(motomirrorCLIVersion)")
            return 0
        case "help", "--help", "-h":
            writeStandardOutput(usageText)
            return 0
        default:
            throw CLIError.usage("Unknown command '\(command)'.\n\n\(usageText)")
        }
    }

    // MARK: doctor

    static func doctor(_ arguments: [String]) async throws -> Int32 {
        let options = try CommandOptions(arguments, flagOptions: ["json"])
        let adbURL = ToolLocator.adb()
        let scrcpyURL = ToolLocator.scrcpy()
        let ffmpegURL = ToolLocator.ffmpeg()

        var resolvedADBVersion: String?
        if let adbURL {
            resolvedADBVersion = await toolVersion(executable: adbURL, arguments: ["version"])
        }
        var resolvedScrcpyVersion: String?
        if let scrcpyURL {
            resolvedScrcpyVersion = await toolVersion(executable: scrcpyURL, arguments: ["--version"])
        }

        var deviceCount = 0
        if let adbURL {
            let client = makeADBClient(adbURL: adbURL)
            if let devices = try? await client.devices() {
                deviceCount = devices.count
            }
        }

        let ok = adbURL != nil && scrcpyURL != nil && ffmpegURL != nil
        let payload = DoctorPayload(
            adb: adbURL?.path,
            scrcpy: scrcpyURL?.path,
            ffmpeg: ffmpegURL?.path,
            adbVersion: resolvedADBVersion,
            scrcpyVersion: resolvedScrcpyVersion,
            deviceCount: deviceCount,
            ok: ok
        )

        if options.flags.contains("json") {
            writeStandardOutput(try jsonString(payload))
        } else {
            writeStandardOutput("adb:      \(payload.adb ?? "MISSING")\(payload.adbVersion.map { " (\($0))" } ?? "")")
            writeStandardOutput("scrcpy:   \(payload.scrcpy ?? "MISSING")\(payload.scrcpyVersion.map { " (\($0))" } ?? "")")
            writeStandardOutput("ffmpeg:   \(payload.ffmpeg ?? "MISSING")")
            writeStandardOutput("devices:  \(deviceCount)")
            writeStandardOutput("status:   \(ok ? "OK" : "MISSING TOOLS")")
        }
        return ok ? 0 : 1
    }

    // MARK: devices

    static func devices(_ arguments: [String]) async throws -> Int32 {
        let options = try CommandOptions(arguments, flagOptions: ["json"])
        let adbURL = try ToolLocator.requireADB()
        let devices = try await makeADBClient(adbURL: adbURL).devices()

        if options.flags.contains("json") {
            writeStandardOutput(try jsonString(devices.map(DevicePayload.init)))
            return 0
        }

        guard !devices.isEmpty else {
            writeStandardOutput("No devices connected.")
            return 0
        }

        let payloads = devices.map(DevicePayload.init)
        let serialWidth = max(6, payloads.map(\.serial.count).max() ?? 6)
        let stateWidth = max(5, payloads.map(\.state.count).max() ?? 5)
        let modelWidth = max(5, payloads.map { ($0.model ?? "-").count }.max() ?? 5)
        writeStandardOutput(
            pad("SERIAL", serialWidth) + "  " + pad("STATE", stateWidth) + "  "
                + pad("MODEL", modelWidth) + "  TRANSPORT"
        )
        for payload in payloads {
            writeStandardOutput(
                pad(payload.serial, serialWidth) + "  " + pad(payload.state, stateWidth) + "  "
                    + pad(payload.model ?? "-", modelWidth) + "  " + payload.transport
            )
        }
        return 0
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    // MARK: info

    static func info(_ arguments: [String]) async throws -> Int32 {
        let options = try CommandOptions(
            arguments,
            valueOptions: ["serial"],
            flagOptions: ["json"]
        )
        let serial = try options.required("serial")
        let adbURL = try ToolLocator.requireADB()
        let client = makeADBClient(adbURL: adbURL)
        let devices = try await client.devices()
        guard let device = devices.first(where: { $0.serial == serial }) else {
            throw CLIError.failure(
                "Device \(serial) is not connected. Run 'motomirrorctl devices'."
            )
        }
        guard device.state == .device else {
            throw CLIError.failure(
                "Device \(serial) is \(device.state.rawValue). Accept the USB debugging prompt on the phone."
            )
        }
        let details = try await client.details(for: serial)
        let payload = InfoPayload(details)

        if options.flags.contains("json") {
            writeStandardOutput(try jsonString(payload))
            return 0
        }

        writeStandardOutput("serial:          \(details.serial)")
        writeStandardOutput("manufacturer:    \(details.manufacturer ?? "-")")
        writeStandardOutput("model:           \(details.model ?? "-")")
        writeStandardOutput("androidVersion:  \(details.androidVersion ?? "-")")
        writeStandardOutput("sdk:             \(details.sdk ?? "-")")
        writeStandardOutput("abi:             \(details.abi ?? "-")")
        if let battery = details.battery {
            writeStandardOutput("battery.level:   \(battery.level.map(String.init) ?? "-")")
            writeStandardOutput("battery.status:  \(battery.status ?? "-")")
            writeStandardOutput("battery.isCharging: \(battery.isCharging)")
            writeStandardOutput("battery.tempC:   \(battery.temperatureCelsius.map { String(format: "%.1f", $0) } ?? "-")")
            writeStandardOutput("battery.voltage: \(battery.voltageMillivolts.map(String.init) ?? "-")")
        }
        if let storage = details.storage {
            writeStandardOutput("storage.total:   \(storage.totalBytes)")
            writeStandardOutput("storage.free:    \(storage.availableBytes)")
            writeStandardOutput("storage.used:    \(storage.usedBytes)")
            writeStandardOutput("storage.usedFraction: \(String(format: "%.3f", storage.usedFraction))")
        }
        if let screen = details.screen {
            writeStandardOutput("screen:          \(screen.width)x\(screen.height) @ \(screen.density.map(String.init) ?? "-") dpi")
        }
        return 0
    }

    // MARK: screenshot

    static func screenshot(_ arguments: [String]) async throws -> Int32 {
        let options = try CommandOptions(arguments, valueOptions: ["serial", "out"])
        let serial = try options.required("serial")
        let outputPath = expandedPath(try options.required("out"))
        let adbURL = try ToolLocator.requireADB()
        let data = try await makeADBClient(adbURL: adbURL).screenshot(serial: serial)

        guard !data.isEmpty else {
            throw CLIError.failure("adb returned an empty screenshot for \(serial).")
        }
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.prefix(8) == pngMagic else {
            let prefix = data.prefix(64).map { String(format: "%02x", $0) }.joined()
            throw CLIError.failure("adb screenshot was not a PNG (first bytes: \(prefix)).")
        }

        try ensureParentDirectory(for: outputPath)
        do {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        } catch {
            throw CLIError.failure("Could not write \(outputPath): \(error.localizedDescription)")
        }
        writeStandardOutput("\(outputPath) (\(data.count) bytes)")
        return 0
    }

    // MARK: mirror

    static func mirror(_ arguments: [String]) async throws -> Int32 {
        let options = try CommandOptions(
            arguments,
            valueOptions: ["serial", "duration", "record", "max-size", "max-fps", "bitrate"],
            flagOptions: ["no-audio", "headless", "no-window"]
        )
        let serial = try options.required("serial")
        let duration = try options.double("duration", default: 0)
        guard duration >= 0 else {
            throw CLIError.usage("--duration must be zero or positive.")
        }
        let recordPath = options.string("record").map(expandedPath)
        let maxSize = try options.integer("max-size", default: 0)
        let maxFPS = try options.integer("max-fps", default: 60)
        let bitrate = try options.integer("bitrate", default: 8)

        var extraArguments: [String] = []
        if options.flags.contains("headless") || options.flags.contains("no-window") {
            extraArguments.append("--no-window")
        }
        if options.flags.contains("headless") {
            extraArguments.append("--no-playback")
        }

        var scrcpyOptions = ScrcpyOptions(
            maxSize: maxSize,
            videoBitRateMbps: bitrate,
            maxFPS: maxFPS,
            audioEnabled: !options.flags.contains("no-audio"),
            recordEnabled: recordPath != nil,
            extraArguments: extraArguments
        )
        try ScrcpyCommand.validate(serial: serial, options: scrcpyOptions)

        if let recordPath {
            try ensureParentDirectory(for: recordPath)
            scrcpyOptions.recordEnabled = true
        }

        let toolchain = try ToolLocator.requireToolchain()
        let adbClient = makeADBClient(adbURL: toolchain.adb)

        let devices = try await adbClient.devices()
        guard let device = devices.first(where: { $0.serial == serial }) else {
            throw CLIError.failure("Device \(serial) is not connected. Run 'motomirrorctl devices'.")
        }
        guard device.state == .device else {
            throw CLIError.failure(
                "Device \(serial) is \(device.state.rawValue). Accept the USB debugging prompt on the phone."
            )
        }

        let controller: any ScrcpyControlling = ScrcpyController(
            scrcpyURL: toolchain.scrcpy,
            adbURL: toolchain.adb,
            runner: ProcessRunner()
        )

        try await controller.start(serial: serial, options: scrcpyOptions, recordPath: recordPath)

        let trap = SignalTrap()
        trap.install()
        defer { trap.cancel() }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = duration > 0 ? startedAt + duration : nil
        var sawActive = false
        var sawFailure = false
        var lastState = ScrcpyStatus.State.starting

        while true {
            if trap.isTriggered { break }
            let status = await controller.status()
            lastState = status.state
            if status.isActive { sawActive = true }
            if status.state == .failed {
                sawFailure = true
                break
            }
            if status.state == .stopped && sawActive { break }
            if status.state == .stopped && !sawActive
                && ProcessInfo.processInfo.systemUptime - startedAt > 1.0 {
                break
            }
            if let deadline, ProcessInfo.processInfo.systemUptime >= deadline { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        await controller.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)

        let logs = await controller.logs()
        let tail = Array(logs.suffix(40))
        if tail.isEmpty {
            writeStandardOutput("(no log output)")
        } else {
            for line in tail { writeStandardOutput(line) }
        }

        let finalStatus = await controller.status()
        let ran = sawActive || finalStatus.state == .stopped && (finalStatus.pid != nil)

        var recordingFailed = false
        if let recordPath {
            var waited = 0.0
            while fileSize(recordPath) == 0 && waited < 2.0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 0.1
            }
            recordingFailed = fileSize(recordPath) == 0
        }

        if sawFailure || !ran || finalStatus.state == .failed || recordingFailed {
            let reason: String
            if recordingFailed, let recordPath {
                reason = "recording file is empty: \(recordPath)"
            } else {
                reason = "state: \(lastState.rawValue), exit: "
                    + "\(finalStatus.exitCode.map(String.init) ?? "none")"
            }
            writeStandardError("Mirror session for \(serial) did not complete (\(reason)).")
            return 1
        }

        writeStandardOutput(
            "Mirror session finished for \(serial) after "
                + String(format: "%.1f", ProcessInfo.processInfo.systemUptime - startedAt)
                + "s\(recordPath.map { ", recording: \($0)" } ?? "")."
        )
        return 0
    }

    // MARK: wireless

    static func wireless(_ arguments: [String]) async throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Missing wireless subcommand. Use discover, pair, connect, disconnect, or tcpip."
            )
        }
        let rest = Array(arguments.dropFirst())
        let adbURL = try ToolLocator.requireADB()
        let client = makeADBClient(adbURL: adbURL)

        switch subcommand {
        case "discover":
            let options = try CommandOptions(rest, flagOptions: ["json"])
            let services = try await client.mdnsServices()
            if options.flags.contains("json") {
                writeStandardOutput(try jsonString(services.map(MDNSServicePayload.init)))
            } else if services.isEmpty {
                writeStandardOutput(
                    "No wireless debugging services found. Open the phone's Wireless debugging "
                        + "pairing dialog, keep both devices on the same Wi-Fi, and retry."
                )
            } else {
                for service in services {
                    writeStandardOutput(
                        "\(service.kind.rawValue)\t\(service.hostPort)\t\(service.name)"
                    )
                }
            }
            return 0

        case "pair":
            let options = try CommandOptions(rest, valueOptions: ["host", "port", "code"])
            let host = try validHost(options.required("host"))
            let port = try options.requiredPort("port")
            let code = try options.required("code")
            let result = try await client.pair(host: host, port: port, code: code)
            writeStandardOutput(result.isEmpty ? "Paired with \(host):\(port)." : result)
            return 0

        case "connect":
            let options = try CommandOptions(rest, valueOptions: ["host", "port"])
            let host = try validHost(options.required("host"))
            let port = try options.requiredPort("port")
            let result = try await client.connect(host: host, port: port)
            writeStandardOutput(result.isEmpty ? "Connected to \(host):\(port)." : result)
            return 0

        case "disconnect":
            let options = try CommandOptions(rest, valueOptions: ["host", "port"])
            let host = try validHost(options.required("host"))
            let port = try options.requiredPort("port")
            try await client.disconnect(host: host, port: port)
            writeStandardOutput("Disconnected \(host):\(port).")
            return 0

        case "tcpip":
            let options = try CommandOptions(rest, valueOptions: ["serial", "port"])
            let serial = try options.required("serial")
            let port = try options.port("port", default: 5555)
            try await client.enableTCPIP(serial: serial, port: port)
            writeStandardOutput(
                "TCP/IP mode enabled for \(serial) on port \(port). "
                    + "Connect with: adb connect <phone-ip>:\(port)"
            )
            return 0

        default:
            throw CLIError.usage("Unknown wireless subcommand '\(subcommand)'.")
        }
    }

    // MARK: tailscale

    static func tailscale(_ arguments: [String]) async throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Missing Tailscale subcommand. Use 'tailscale peers' or 'tailscale status'.")
        }
        let rest = Array(arguments.dropFirst())
        let options = try CommandOptions(rest, flagOptions: ["json"])
        guard options.positionals.isEmpty else {
            throw CLIError.usage(
                "Unexpected Tailscale argument '\(options.positionals[0])'. "
                    + "Use 'tailscale peers' or 'tailscale status'."
            )
        }

        guard let cli = TailscaleDiscovery.locateCLI() else {
            throw CLIError.failure(
                "Install Tailscale, then retry. MotoMirror only reads `tailscale status --json`."
            )
        }

        let allPeers: [TailscalePeer]
        do {
            allPeers = try await TailscaleDiscovery.status(
                using: cli,
                runner: ProcessRunner()
            )
        } catch {
            throw CLIError.failure(
                "Could not read Tailscale status: \(error.localizedDescription)"
            )
        }

        let peers: [TailscalePeer]
        switch subcommand {
        case "peers":
            peers = TailscaleDiscovery.androidPeers(from: allPeers)
        case "status":
            peers = sortedTailscalePeers(allPeers)
        default:
            throw CLIError.usage(
                "Unknown Tailscale subcommand '\(subcommand)'. Use peers or status."
            )
        }

        if options.flags.contains("json") {
            writeStandardOutput(try jsonString(peers.map(TailscalePeerPayload.init)))
            return 0
        }

        if peers.isEmpty {
            writeStandardOutput(
                subcommand == "peers"
                    ? "No Android Tailscale peers found."
                    : "No Tailscale peers found."
            )
            return 0
        }

        for peer in peers {
            let state = peer.online ? "online" : "offline"
            let ipv4 = peer.ipv4 ?? "-"
            if let dnsName = peer.dnsName {
                writeStandardOutput("\(state)  \(peer.hostName)  \(ipv4) (\(dnsName))")
            } else {
                writeStandardOutput("\(state)  \(peer.hostName)  \(ipv4)")
            }
        }
        return 0
    }

    static func sortedTailscalePeers(_ peers: [TailscalePeer]) -> [TailscalePeer] {
        peers.sorted { lhs, rhs in
            if lhs.online != rhs.online { return lhs.online }
            let left = lhs.hostName.lowercased()
            let right = rhs.hostName.lowercased()
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    static func validHost(_ host: String) throws -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
            throw CLIError.usage("Host must be a non-empty hostname or IP address.")
        }
        return trimmed
    }
}

// MARK: - SIGINT handling

final class SignalTrap: @unchecked Sendable {
    private let lock = NSLock()
    private var triggered = false
    private var source: DispatchSourceSignal?

    var isTriggered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return triggered
    }

    func install() {
        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        signalSource.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.triggered = true
            self.lock.unlock()
            writeStandardError("Interrupt received, stopping mirror session…")
        }
        signalSource.resume()
        source = signalSource
    }

    func cancel() {
        source?.cancel()
        source = nil
        signal(SIGINT, SIG_DFL)
    }
}

// MARK: - Entry point (top-level code)

let cliArguments = Array(CommandLine.arguments.dropFirst())
let cliStatus: Int32
do {
    cliStatus = try await CLI.run(cliArguments)
} catch let error as CLIError {
    writeStandardError(error.message)
    cliStatus = error.exitCode
} catch {
    writeStandardError("motomirrorctl failed: \(error.localizedDescription)")
    cliStatus = 1
}
exit(cliStatus)
