import Foundation
import MotoMirrorCore

// MARK: - Agent command grouping

enum AgentCLI {
    static func agents(
        _ arguments: [String],
        toolbox: AgentToolbox
    ) async throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Use agent tools or agent call.")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "tools":
            let options = try CommandOptions(rest, flagOptions: ["json"])
            let specs = await toolbox.tools()
            if options.flags.contains("json") {
                let payload: [[String: Any]] = specs.map {
                    ["name": $0.name, "description": $0.description, "inputSchema": $0.inputSchema]
                }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                writeStandardOutput(String(decoding: data, as: UTF8.self))
            } else {
                for spec in specs {
                    writeStandardOutput("\(spec.name)\t\(spec.description)")
                }
            }
            return 0
        case "call":
            let options = try CommandOptions(rest, valueOptions: ["args"], flagOptions: ["json"])
            guard let tool = options.positionals.first else {
                throw CLIError.usage("Use agent call TOOL --args JSON.")
            }
            let json = options.string("args") ?? "{}"
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw CLIError.usage("--args must be a JSON object.")
            }
            let result = try await toolbox.call(tool, arguments: object)
            if options.flags.contains("json") {
                var payload: [String: Any] = ["text": result.text, "isError": result.isError]
                if let image = result.imageBase64 { payload["imageBase64"] = image }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                writeStandardOutput(String(decoding: data, as: UTF8.self))
            } else {
                writeStandardOutput(result.text)
            }
            return result.isError ? 1 : 0
        default:
            throw CLIError.usage("Unknown agent subcommand '\(subcommand)'.")
        }
    }

    static func apps(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Use apps list, current, launch, stop, install, or uninstall.")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "system", "usb"])
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            let apps = try await toolbox.actions.packages(serial: serial, includeSystem: options.flags.contains("system"))
            if options.flags.contains("json") {
                writeStandardOutput(try encode(apps))
            } else {
                for app in apps { writeStandardOutput(app.package) }
            }
            return 0
        case "current":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            guard let app = try await toolbox.actions.foregroundApp(serial: serial) else {
                writeStandardOutput("No foreground app.")
                return 1
            }
            if options.flags.contains("json") { writeStandardOutput(try encode(app)) }
            else { writeStandardOutput("\(app.package)\t\(app.activity ?? "-")") }
            return 0
        case "launch":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
            guard let package = options.positionals.first else { throw CLIError.usage("Missing package.") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            let component = try await toolbox.actions.launchApp(serial: serial, package: package)
            writeStandardOutput("launched \(package) (\(component))")
            return 0
        case "stop":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
            guard let package = options.positionals.first else { throw CLIError.usage("Missing package.") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            try await toolbox.actions.stopApp(serial: serial, package: package)
            writeStandardOutput("stopped \(package)")
            return 0
        case "install":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
            guard let path = options.positionals.first else { throw CLIError.usage("Missing APK path.") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            writeStandardOutput(try await toolbox.actions.install(serial: serial, apk: path))
            return 0
        case "uninstall":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
            guard let package = options.positionals.first else { throw CLIError.usage("Missing package.") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            writeStandardOutput(try await toolbox.actions.uninstall(serial: serial, package: package))
            return 0
        default:
            throw CLIError.usage("Unknown apps subcommand '\(subcommand)'.")
        }
    }

    static func ui(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Use ui dump, find, tap, text, key, or swipe.")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "dump":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "xml", "usb"])
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            let hierarchy = try await toolbox.actions.hierarchy(serial: serial)
            if options.flags.contains("json") {
                writeStandardOutput(try encode(hierarchy))
            } else if options.flags.contains("xml") {
                writeStandardOutput(try encode(hierarchy))
            } else {
                for element in hierarchy.elements {
                    writeStandardOutput("\(element.label)\t\(element.className ?? "-")\t\(element.bounds.x),\(element.bounds.y),\(element.bounds.width),\(element.bounds.height)")
                }
            }
            return 0
        case "find":
            let options = try CommandOptions(rest, valueOptions: ["serial", "text", "id", "desc"], flagOptions: ["json", "usb"])
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            let hierarchy = try await toolbox.actions.hierarchy(serial: serial)
            let matches = filter(hierarchy, options: options)
            if options.flags.contains("json") { writeStandardOutput(try encode(matches)) }
            else { for element in matches { writeStandardOutput("\(element.label)\t\(element.bounds.x),\(element.bounds.y)") } }
            return matches.isEmpty ? 1 : 0
        case "tap":
            let options = try CommandOptions(rest, valueOptions: ["serial", "text", "id", "desc", "x", "y"], flagOptions: ["usb"])
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            if let x = try options.optionalInteger("x"), let y = try options.optionalInteger("y") {
                try await toolbox.actions.tap(serial: serial, x: x, y: y)
                writeStandardOutput("tapped \(x),\(y)")
                return 0
            }
            let hierarchy = try await toolbox.actions.hierarchy(serial: serial)
            guard let element = filter(hierarchy, options: options).first else {
                throw CLIError.failure("No UI element matched.")
            }
            try await toolbox.actions.tap(serial: serial, x: element.bounds.centerX, y: element.bounds.centerY)
            writeStandardOutput("tapped \(element.label) at \(element.bounds.centerX),\(element.bounds.centerY)")
            return 0
        case "text":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["usb"])
            guard let text = options.positionals.first else { throw CLIError.usage("Missing text.") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            try await toolbox.actions.inputText(serial: serial, text: text)
            writeStandardOutput("typed text")
            return 0
        case "key":
            let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["usb"])
            guard let key = options.positionals.first else { throw CLIError.usage("Missing key.") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            try await toolbox.actions.key(serial: serial, key: key)
            writeStandardOutput("sent \(key)")
            return 0
        case "swipe":
            let options = try CommandOptions(rest, valueOptions: ["serial", "duration"], flagOptions: ["usb"])
            guard options.positionals.count >= 4,
                  let x1 = Int(options.positionals[0]),
                  let y1 = Int(options.positionals[1]),
                  let x2 = Int(options.positionals[2]),
                  let y2 = Int(options.positionals[3])
            else { throw CLIError.usage("Use ui swipe X1 Y1 X2 Y2 [--duration MS].") }
            let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
            try await toolbox.actions.swipe(
                serial: serial, x1: x1, y1: y1, x2: x2, y2: y2,
                durationMS: try options.integer("duration", default: 300)
            )
            writeStandardOutput("swiped")
            return 0
        default:
            throw CLIError.usage("Unknown ui subcommand '\(subcommand)'.")
        }
    }

    static func files(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Use files push, pull, or ls.")
        }
        let rest = Array(arguments.dropFirst())
        let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        switch subcommand {
        case "push":
            guard options.positionals.count >= 2 else { throw CLIError.usage("Use files push LOCAL REMOTE.") }
            writeStandardOutput(try await toolbox.actions.push(serial: serial, local: options.positionals[0], remote: options.positionals[1]))
        case "pull":
            guard options.positionals.count >= 2 else { throw CLIError.usage("Use files pull REMOTE LOCAL.") }
            writeStandardOutput(try await toolbox.actions.pull(serial: serial, remote: options.positionals[0], local: options.positionals[1]))
        case "ls":
            guard let remote = options.positionals.first else { throw CLIError.usage("Use files ls REMOTE.") }
            let files = try await toolbox.actions.listFiles(serial: serial, remote: remote)
            if options.flags.contains("json") { writeStandardOutput(try encode(files)) }
            else { for file in files { writeStandardOutput(file) } }
        default:
            throw CLIError.usage("Unknown files subcommand '\(subcommand)'.")
        }
        return 0
    }

    static func open(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        let options = try CommandOptions(arguments, valueOptions: ["serial"], flagOptions: ["usb"])
        guard let url = options.positionals.first else { throw CLIError.usage("Use open URL.") }
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        try await toolbox.actions.openURL(serial: serial, url: url)
        writeStandardOutput("opened \(url)")
        return 0
    }

    static func screen(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        guard let action = arguments.first else { throw CLIError.usage("Use screen wake, sleep, or rotate N.") }
        let rest = Array(arguments.dropFirst())
        let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["usb"])
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        switch action {
        case "wake": try await toolbox.actions.wake(serial: serial)
        case "sleep": try await toolbox.actions.sleep(serial: serial)
        case "rotate":
            guard let rotation = options.positionals.first.flatMap(Int.init) else {
                throw CLIError.usage("Use screen rotate 0|1|2|3.")
            }
            try await toolbox.actions.rotate(serial: serial, rotation: rotation)
        default: throw CLIError.usage("Unknown screen action '\(action)'.")
        }
        writeStandardOutput("screen \(action)")
        return 0
    }

    static func volume(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        guard let action = arguments.first else { throw CLIError.usage("Use volume get or volume set N.") }
        let rest = Array(arguments.dropFirst())
        let options = try CommandOptions(rest, valueOptions: ["serial"], flagOptions: ["json", "usb"])
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        switch action {
        case "get":
            let info = try await toolbox.actions.volume(serial: serial)
            if options.flags.contains("json") { writeStandardOutput(try encode(info)) }
            else { writeStandardOutput("\(info.level)/\(info.max)") }
        case "set":
            guard let level = options.positionals.first.flatMap(Int.init) else {
                throw CLIError.usage("Use volume set N.")
            }
            try await toolbox.actions.setVolume(serial: serial, level: level)
            writeStandardOutput("volume \(level)")
        default: throw CLIError.usage("Unknown volume action '\(action)'.")
        }
        return 0
    }

    static func shell(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        let options = try CommandOptions(arguments, valueOptions: ["serial", "timeout"], flagOptions: ["json", "usb"])
        let command = options.positionals.joined(separator: " ")
        guard !command.isEmpty else { throw CLIError.usage("Missing shell command.") }
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        let output = try await toolbox.actions.shell(serial: serial, command: command, timeout: try options.double("timeout", default: 30))
        writeStandardOutput("exit=\(output.status)")
        if !output.stdout.isEmpty { writeStandardOutput(output.stdout) }
        if !output.stderr.isEmpty { writeStandardError(output.stderr) }
        return output.succeeded ? 0 : 1
    }

    static func logcat(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        let options = try CommandOptions(arguments, valueOptions: ["serial", "n"], flagOptions: ["json", "usb"])
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        writeStandardOutput(try await toolbox.actions.logcat(serial: serial, lines: try options.integer("n", default: 200)))
        return 0
    }

    static func waitFor(_ arguments: [String], toolbox: AgentToolbox) async throws -> Int32 {
        guard let kind = arguments.first else { throw CLIError.usage("Use wait-for app PACKAGE or wait-for device.") }
        let rest = Array(arguments.dropFirst())
        let options = try CommandOptions(rest, valueOptions: ["serial", "timeout"], flagOptions: ["usb"])
        if kind == "device" {
            let deadline = Date().addingTimeInterval(try options.double("timeout", default: 30))
            while Date() < deadline {
                if let devices = try? await toolbox.client.devices(),
                   devices.contains(where: { $0.state == .device }) {
                    writeStandardOutput("device ready")
                    return 0
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            throw CLIError.failure("Timed out waiting for a device.")
        }
        guard kind == "app", let package = options.positionals.first else {
            throw CLIError.usage("Use wait-for app PACKAGE or wait-for device.")
        }
        let serial = try await DeviceResolver.resolve(toolbox: toolbox, options: options)
        try await toolbox.actions.waitForApp(serial: serial, package: package, timeout: try options.double("timeout", default: 15))
        writeStandardOutput("app \(package) is foreground")
        return 0
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func filter(_ hierarchy: UIHierarchy, options: CommandOptions) -> [UIElement] {
        hierarchy.elements.filter { element in
            if let text = options.string("text"), !text.isEmpty {
                return element.text?.localizedCaseInsensitiveContains(text) == true
            }
            if let id = options.string("id"), !id.isEmpty {
                return element.resourceID?.localizedCaseInsensitiveContains(id) == true
            }
            if let desc = options.string("desc"), !desc.isEmpty {
                return element.contentDescription?.localizedCaseInsensitiveContains(desc) == true
            }
            return false
        }
    }
}

enum DeviceResolver {
    static func resolve(toolbox: AgentToolbox, options: CommandOptions) async throws -> String {
        let usbOnly = options.flags.contains("usb")
            || ProcessInfo.processInfo.environment["MOTOMIRROR_TRANSPORT"]?.lowercased() == "usb"
        let devices = try await toolbox.client.devices()
        if let serial = options.string("serial") {
            if usbOnly {
                guard let device = devices.first(where: { $0.serial == serial }),
                      device.transport == .usb
                else {
                    throw CLIError.failure(
                        "USB only is enabled and \(serial) is not a USB device. "
                            + "Connect a USB data cable; wireless debugging is not required."
                    )
                }
            }
            return serial
        }
        let usable = devices.filter { $0.state == .device && (!usbOnly || $0.transport == .usb) }
        guard let device = usable.first else {
            if usbOnly {
                throw CLIError.failure(
                    "No USB device. Connect a USB data cable and authorize USB debugging; "
                        + "wireless debugging is not required."
                )
            }
            throw CLIError.failure("No usable Android device.")
        }
        return device.serial
    }
}
