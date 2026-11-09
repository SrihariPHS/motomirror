import Foundation

public enum ScrcpyCommand {
    public static func arguments(
        serial: String,
        options: ScrcpyOptions,
        recordPath: String? = nil
    ) -> [String] {
        var arguments: [String] = [
            "--serial=\(serial)",
            "--window-title=\(options.windowTitle(deviceName: serial))"
        ]

        let maxSize = min(max(options.maxSize, 0), 4096)
        if maxSize > 0 {
            arguments.append("--max-size=\(maxSize)")
        }

        let bitRate = min(max(options.videoBitRateMbps, 1), 100)
        arguments.append("--video-bit-rate=\(bitRate)M")

        let fps = min(max(options.maxFPS, 0), 240)
        if fps > 0 {
            arguments.append("--max-fps=\(fps)")
        }

        if !options.audioEnabled {
            arguments.append("--no-audio")
        }
        if options.stayAwake {
            arguments.append("--stay-awake")
        }
        if options.turnScreenOff {
            arguments.append("--turn-screen-off")
        }
        if options.showTouches {
            arguments.append("--show-touches")
        }
        if options.alwaysOnTop {
            arguments.append("--always-on-top")
        }
        if options.fullscreen {
            arguments.append("--fullscreen")
        }

        if let recordPath, !recordPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append("--record=\(recordPath)")
        }

        arguments.append(contentsOf: options.extraArguments)
        return arguments
    }

    public static func validate(serial: String, options: ScrcpyOptions) throws {
        let trimmedSerial = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSerial.isEmpty, !trimmedSerial.contains(where: \.isWhitespace) else {
            throw MotoMirrorError.invalidInput("The device serial is empty or malformed.")
        }
        guard options.videoBitRateMbps > 0 else {
            throw MotoMirrorError.invalidInput("Video bit rate must be greater than zero.")
        }
        guard options.maxSize == 0 || (160...4096).contains(options.maxSize) else {
            throw MotoMirrorError.invalidInput("Max size must be 0 (native) or between 160 and 4096 pixels.")
        }
        guard (0...240).contains(options.maxFPS) else {
            throw MotoMirrorError.invalidInput("Max FPS must be between 0 and 240.")
        }
    }
}

public extension ScrcpyOptions {
    func windowTitle(deviceName: String) -> String {
        let suffix = "MotoMirror"
        if deviceName.isEmpty { return suffix }
        return "\(deviceName) — \(suffix)"
    }
}
