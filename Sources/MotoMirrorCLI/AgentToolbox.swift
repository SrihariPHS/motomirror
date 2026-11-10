import Foundation
import MotoMirrorCore

struct AgentToolSpec {
    let name: String
    let description: String
    let inputSchema: [String: Any]
}

struct AgentToolResult {
    let text: String
    let imageBase64: String?
    let isError: Bool

    init(text: String, imageBase64: String? = nil, isError: Bool = false) {
        self.text = text
        self.imageBase64 = imageBase64
        self.isError = isError
    }
}

actor AgentToolbox {
    let client: ADBClient
    let actions: DeviceActions
    let scrcpy: ScrcpyController?

    init(adbURL: URL, scrcpyURL: URL?) {
        client = ADBClient(adbURL: adbURL, runner: ProcessRunner())
        actions = DeviceActions(adbURL: adbURL, runner: ProcessRunner())
        if let scrcpyURL {
            scrcpy = ScrcpyController(scrcpyURL: scrcpyURL, adbURL: adbURL, runner: ProcessRunner())
        } else {
            scrcpy = nil
        }
    }

    func tools() -> [AgentToolSpec] {
        let serial: [String: Any] = ["type": "string", "description": "ADB serial. Defaults to the first device."]
        func schema(_ properties: [(String, [String: Any])], required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": Dictionary(uniqueKeysWithValues: properties), "required": required]
        }
        return [
            AgentToolSpec(name: "devices_list", description: "List connected Android devices.", inputSchema: schema([])),
            AgentToolSpec(name: "device_info", description: "Model, Android version, battery, storage, and screen.", inputSchema: schema([("serial", serial)])),
            AgentToolSpec(name: "screenshot", description: "Capture a PNG screenshot and return its path plus base64.", inputSchema: schema([("serial", serial), ("path", ["type": "string"])])),
            AgentToolSpec(name: "apps_list", description: "List installed app packages.", inputSchema: schema([("serial", serial), ("includeSystem", ["type": "boolean"])])),
            AgentToolSpec(name: "apps_current", description: "Return the foreground app package and activity.", inputSchema: schema([("serial", serial)])),
            AgentToolSpec(name: "apps_launch", description: "Launch an app by package.", inputSchema: schema([("serial", serial), ("package", ["type": "string"])], required: ["package"])),
            AgentToolSpec(name: "apps_stop", description: "Force-stop an app by package.", inputSchema: schema([("serial", serial), ("package", ["type": "string"])], required: ["package"])),
            AgentToolSpec(name: "apps_install", description: "Install an APK from this Mac.", inputSchema: schema([("serial", serial), ("apk", ["type": "string"])], required: ["apk"])),
            AgentToolSpec(name: "apps_uninstall", description: "Uninstall a package.", inputSchema: schema([("serial", serial), ("package", ["type": "string"])], required: ["package"])),
            AgentToolSpec(name: "open_url", description: "Open a URL or deep link on the phone.", inputSchema: schema([("serial", serial), ("url", ["type": "string"])], required: ["url"])),
            AgentToolSpec(name: "ui_dump", description: "Dump the accessibility UI hierarchy.", inputSchema: schema([("serial", serial)])),
            AgentToolSpec(name: "ui_find", description: "Find UI elements by text, resource id, or content description.", inputSchema: schema([("serial", serial), ("text", ["type": "string"]), ("id", ["type": "string"]), ("desc", ["type": "string"])])),
            AgentToolSpec(name: "ui_tap", description: "Tap a UI element by text/id/desc, or coordinates.", inputSchema: schema([("serial", serial), ("text", ["type": "string"]), ("id", ["type": "string"]), ("desc", ["type": "string"]), ("x", ["type": "integer"]), ("y", ["type": "integer"])])),
            AgentToolSpec(name: "input_text", description: "Type text into the focused field.", inputSchema: schema([("serial", serial), ("text", ["type": "string"])], required: ["text"])),
            AgentToolSpec(name: "input_key", description: "Send an Android key event name.", inputSchema: schema([("serial", serial), ("key", ["type": "string"])], required: ["key"])),
            AgentToolSpec(name: "swipe", description: "Swipe between two points.", inputSchema: schema([("serial", serial), ("x1", ["type": "integer"]), ("y1", ["type": "integer"]), ("x2", ["type": "integer"]), ("y2", ["type": "integer"]), ("durationMS", ["type": "integer"])], required: ["x1", "y1", "x2", "y2"])),
            AgentToolSpec(name: "files_push", description: "Copy a file from the Mac to the phone.", inputSchema: schema([("serial", serial), ("local", ["type": "string"]), ("remote", ["type": "string"])], required: ["local", "remote"])),
            AgentToolSpec(name: "files_pull", description: "Copy a file from the phone to the Mac.", inputSchema: schema([("serial", serial), ("remote", ["type": "string"]), ("local", ["type": "string"])], required: ["remote", "local"])),
            AgentToolSpec(name: "files_ls", description: "List a directory on the phone.", inputSchema: schema([("serial", serial), ("remote", ["type": "string"])], required: ["remote"])),
            AgentToolSpec(name: "shell", description: "Run an adb shell command on the phone.", inputSchema: schema([("serial", serial), ("command", ["type": "string"]), ("timeout", ["type": "number"])], required: ["command"])),
            AgentToolSpec(name: "screen", description: "Wake, sleep, or rotate the screen.", inputSchema: schema([("serial", serial), ("action", ["type": "string", "enum": ["wake", "sleep", "rotate"]]), ("rotation", ["type": "integer"])], required: ["action"])),
            AgentToolSpec(name: "volume", description: "Get or set media volume.", inputSchema: schema([("serial", serial), ("action", ["type": "string", "enum": ["get", "set"]]), ("level", ["type": "integer"])], required: ["action"])),
            AgentToolSpec(name: "logcat", description: "Read recent logcat lines.", inputSchema: schema([("serial", serial), ("lines", ["type": "integer"])])),
            AgentToolSpec(name: "wait_for_app", description: "Wait until a package is foreground.", inputSchema: schema([("serial", serial), ("package", ["type": "string"]), ("timeout", ["type": "number"])], required: ["package"])),
            AgentToolSpec(name: "mirror_start", description: "Start a mirror session.", inputSchema: schema([("serial", serial), ("preset", ["type": "string", "enum": ["quality", "balanced", "batterySaver"]])])),
            AgentToolSpec(name: "mirror_stop", description: "Stop the current mirror session.", inputSchema: schema([])),
            AgentToolSpec(name: "mirror_status", description: "Return mirror session status.", inputSchema: schema([]))
        ]
    }

    func call(_ name: String, arguments: [String: Any]) async throws -> AgentToolResult {
        do {
            let serial = try await resolveSerial(arguments["serial"] as? String)
            switch name {
            case "devices_list":
                let devices = try await client.devices()
                return .init(text: try encode(devices))
            case "device_info":
                return .init(text: try encode(try await client.details(for: serial)))
            case "screenshot":
                let data = try await client.screenshot(serial: serial)
                let requested = (arguments["path"] as? String)?.trimmingCharacters(in: .whitespaces)
                let path = requested?.isEmpty == false
                    ? expandedPath(requested!)
                    : "/tmp/motomirror-mcp-\(Int(Date().timeIntervalSince1970)).png"
                try ensureParent(path)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                return .init(
                    text: "Screenshot: \(path) (\(data.count) bytes)",
                    imageBase64: data.base64EncodedString()
                )
            case "apps_list":
                let includeSystem = arguments["includeSystem"] as? Bool ?? false
                return .init(text: try encode(try await actions.packages(serial: serial, includeSystem: includeSystem)))
            case "apps_current":
                return .init(text: try encode(try await actions.foregroundApp(serial: serial)))
            case "apps_launch":
                let package = try requiredString("package", arguments)
                return .init(text: "Launched \(package) (\(try await actions.launchApp(serial: serial, package: package)))")
            case "apps_stop":
                let package = try requiredString("package", arguments)
                try await actions.stopApp(serial: serial, package: package)
                return .init(text: "Stopped \(package)")
            case "apps_install":
                return .init(text: try await actions.install(serial: serial, apk: try requiredString("apk", arguments)))
            case "apps_uninstall":
                return .init(text: try await actions.uninstall(serial: serial, package: try requiredString("package", arguments)))
            case "open_url":
                try await actions.openURL(serial: serial, url: try requiredString("url", arguments))
                return .init(text: "Opened URL")
            case "ui_dump":
                return .init(text: try encode(try await actions.hierarchy(serial: serial)))
            case "ui_find", "ui_tap":
                let hierarchy = try await actions.hierarchy(serial: serial)
                if name == "ui_tap", let x = argumentInt("x", arguments), let y = argumentInt("y", arguments) {
                    try await actions.tap(serial: serial, x: x, y: y)
                    return .init(text: "Tapped \(x),\(y)")
                }
                let matches = hierarchy.elements.filter { element in
                    if let text = arguments["text"] as? String, !text.isEmpty {
                        return element.text?.localizedCaseInsensitiveContains(text) == true
                    }
                    if let id = arguments["id"] as? String, !id.isEmpty {
                        return element.resourceID?.localizedCaseInsensitiveContains(id) == true
                    }
                    if let desc = arguments["desc"] as? String, !desc.isEmpty {
                        return element.contentDescription?.localizedCaseInsensitiveContains(desc) == true
                    }
                    return false
                }
                if name == "ui_tap" {
                    guard let first = matches.first else {
                        throw MotoMirrorError.invalidInput("No UI element matched.")
                    }
                    try await actions.tap(serial: serial, x: first.bounds.centerX, y: first.bounds.centerY)
                    return .init(text: "Tapped \(first.label) at \(first.bounds.centerX),\(first.bounds.centerY)")
                }
                return .init(text: try encode(matches))
            case "input_text":
                try await actions.inputText(serial: serial, text: try requiredString("text", arguments))
                return .init(text: "Typed text")
            case "input_key":
                try await actions.key(serial: serial, key: try requiredString("key", arguments))
                return .init(text: "Sent key")
            case "swipe":
                try await actions.swipe(
                    serial: serial,
                    x1: try requiredInt("x1", arguments), y1: try requiredInt("y1", arguments),
                    x2: try requiredInt("x2", arguments), y2: try requiredInt("y2", arguments),
                    durationMS: argumentInt("durationMS", arguments) ?? 300
                )
                return .init(text: "Swiped")
            case "files_push":
                return .init(text: try await actions.push(
                    serial: serial,
                    local: try requiredString("local", arguments),
                    remote: try requiredString("remote", arguments)
                ))
            case "files_pull":
                return .init(text: try await actions.pull(
                    serial: serial,
                    remote: try requiredString("remote", arguments),
                    local: try requiredString("local", arguments)
                ))
            case "files_ls":
                return .init(text: try encode(try await actions.listFiles(
                    serial: serial, remote: try requiredString("remote", arguments)
                )))
            case "shell":
                let output = try await actions.shell(
                    serial: serial,
                    command: try requiredString("command", arguments),
                    timeout: (arguments["timeout"] as? Double) ?? 30
                )
                return .init(
                    text: "exit=\(output.status)\n\(output.stdout)\(output.stderr)",
                    isError: !output.succeeded
                )
            case "screen":
                let action = try requiredString("action", arguments)
                switch action {
                case "wake": try await actions.wake(serial: serial)
                case "sleep": try await actions.sleep(serial: serial)
                case "rotate": try await actions.rotate(serial: serial, rotation: try requiredInt("rotation", arguments))
                default: throw MotoMirrorError.invalidInput("screen action must be wake, sleep, or rotate.")
                }
                return .init(text: "Screen \(action)")
            case "volume":
                let action = try requiredString("action", arguments)
                if action == "get" {
                    return .init(text: try encode(try await actions.volume(serial: serial)))
                }
                guard action == "set" else {
                    throw MotoMirrorError.invalidInput("volume action must be get or set.")
                }
                try await actions.setVolume(serial: serial, level: try requiredInt("level", arguments))
                return .init(text: "Volume set")
            case "logcat":
                return .init(text: try await actions.logcat(
                    serial: serial, lines: argumentInt("lines", arguments) ?? 200
                ))
            case "wait_for_app":
                try await actions.waitForApp(
                    serial: serial,
                    package: try requiredString("package", arguments),
                    timeout: (arguments["timeout"] as? Double) ?? 15
                )
                return .init(text: "App is foreground")
            case "mirror_start":
                guard let scrcpy else { throw MotoMirrorError.toolMissing("scrcpy") }
                let preset = MirrorPreset(rawValue: (arguments["preset"] as? String) ?? "balanced") ?? .balanced
                guard let options = preset.options else {
                    throw MotoMirrorError.invalidInput("Custom preset has no fixed options.")
                }
                try await scrcpy.start(serial: serial, options: options, recordPath: nil)
                return .init(text: "Mirror started with \(preset.rawValue)")
            case "mirror_stop":
                await scrcpy?.stop()
                return .init(text: "Mirror stopped")
            case "mirror_status":
                return .init(text: try encode(await scrcpy?.status() ?? ScrcpyStatus()))
            default:
                throw MotoMirrorError.invalidInput("Unknown tool \(name).")
            }
        } catch {
            return .init(text: error.localizedDescription, isError: true)
        }
    }

    private func resolveSerial(_ requested: String?) async throws -> String {
        if let requested = requested?.trimmingCharacters(in: .whitespaces), !requested.isEmpty {
            return requested
        }
        let devices = try await client.devices()
        guard let device = devices.first(where: { $0.state == .device }) else {
            throw MotoMirrorError.deviceNotFound("any device")
        }
        return device.serial
    }

    private func requiredString(_ key: String, _ args: [String: Any]) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else {
            throw MotoMirrorError.invalidInput("Missing argument \(key).")
        }
        return value
    }

    private func requiredInt(_ key: String, _ args: [String: Any]) throws -> Int {
        guard let value = argumentInt(key, args) else {
            throw MotoMirrorError.invalidInput("Missing integer argument \(key).")
        }
        return value
    }

    private func argumentInt(_ key: String, _ args: [String: Any]) -> Int? {
        if let value = args[key] as? Int { return value }
        if let value = args[key] as? NSNumber { return value.intValue }
        if let value = args[key] as? String { return Int(value) }
        return nil
    }

    private func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func ensureParent(_ path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
