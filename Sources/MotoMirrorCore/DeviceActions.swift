import Foundation

public struct InstalledApp: Codable, Equatable, Sendable {
    public let package: String
    public init(package: String) { self.package = package }
}

public struct ForegroundApp: Codable, Equatable, Sendable {
    public let package: String
    public let activity: String?
    public init(package: String, activity: String? = nil) {
        self.package = package
        self.activity = activity
    }
}

public struct VolumeInfo: Codable, Equatable, Sendable {
    public let level: Int
    public let max: Int
    public init(level: Int, max: Int) {
        self.level = level
        self.max = max
    }
}

public actor DeviceActions {
    private let adbURL: URL
    private let runner: ProcessRunner

    public init(adbURL: URL, runner: ProcessRunner = ProcessRunner()) {
        self.adbURL = adbURL
        self.runner = runner
    }

    // MARK: - Apps

    public func packages(serial: String, includeSystem: Bool) async throws -> [InstalledApp] {
        let serial = try validatedSerial(serial)
        var arguments = ["-s", serial, "shell", "pm", "list", "packages"]
        if !includeSystem { arguments.append("-3") }
        let output = try await run(arguments, timeout: 30)
        try output.requireSuccess("adb")
        return DeviceOutputParser.packages(output.stdout)
    }

    public func foregroundApp(serial: String) async throws -> ForegroundApp? {
        let serial = try validatedSerial(serial)
        let output = try await run(
            ["-s", serial, "shell", "dumpsys", "activity", "activities"],
            timeout: 25
        )
        try output.requireSuccess("adb")
        return DeviceOutputParser.foreground(output.stdout)
    }

    public func launchApp(serial: String, package: String) async throws -> String {
        let serial = try validatedSerial(serial)
        let package = try validatedPackage(package)
        let resolved = try await run(
            [
                "-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief",
                "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER",
                package
            ],
            timeout: 25
        )
        try resolved.requireSuccess("adb")
        guard let component = resolved.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { $0.contains("/") && !$0.contains(" ") })
        else {
            throw MotoMirrorError.invalidInput("\(package) has no launcher activity.")
        }
        let started = try await run(
            ["-s", serial, "shell", "am", "start", "-n", component],
            timeout: 30
        )
        try started.requireSuccess("adb")
        let text = started.stdout + started.stderr
        if text.lowercased().contains("error") {
            throw MotoMirrorError.commandFailed(
                executable: "am start", code: started.status, stderr: text
            )
        }
        return component
    }

    public func stopApp(serial: String, package: String) async throws {
        let serial = try validatedSerial(serial)
        let package = try validatedPackage(package)
        let output = try await run(
            ["-s", serial, "shell", "am", "force-stop", package], timeout: 25
        )
        try output.requireSuccess("adb")
    }

    public func install(serial: String, apk: String) async throws -> String {
        let serial = try validatedSerial(serial)
        let path = (apk as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw MotoMirrorError.invalidInput("APK not found: \(path)")
        }
        let output = try await run(
            ["-s", serial, "install", "-r", "-g", path], timeout: 180
        )
        let text = output.stdout + output.stderr
        guard output.succeeded, text.lowercased().contains("success") else {
            throw MotoMirrorError.commandFailed(
                executable: "adb install", code: output.status, stderr: text
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func uninstall(serial: String, package: String) async throws -> String {
        let serial = try validatedSerial(serial)
        let package = try validatedPackage(package)
        let output = try await run(
            ["-s", serial, "uninstall", package], timeout: 60
        )
        let text = output.stdout + output.stderr
        guard output.succeeded, text.lowercased().contains("success") else {
            throw MotoMirrorError.commandFailed(
                executable: "adb uninstall", code: output.status, stderr: text
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func openURL(serial: String, url: String) async throws {
        let serial = try validatedSerial(serial)
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https", "mailto", "tel"].contains(scheme)
        else {
            throw MotoMirrorError.invalidInput(
                "URL must be http, https, mailto, or tel without whitespace."
            )
        }
        let output = try await run(
            ["-s", serial, "shell", "am", "start", "-a", "android.intent.action.VIEW",
             "-d", shellQuote(trimmed)],
            timeout: 25
        )
        try output.requireSuccess("adb")
    }

    // MARK: - UI

    public func hierarchy(serial: String) async throws -> UIHierarchy {
        let serial = try validatedSerial(serial)
        let remote = "/sdcard/motomirror-agent-ui.xml"
        var lastError = "uiautomator produced no hierarchy."
        for attempt in 1...3 {
            let dump = try await run(
                ["-s", serial, "shell", "uiautomator", "dump", remote], timeout: 45
            )
            if dump.succeeded {
                let fetched = try await run(
                    ["-s", serial, "exec-out", "cat", remote], timeout: 30
                )
                if fetched.succeeded, fetched.stdout.contains("<hierarchy") {
                    _ = try? await run(
                        ["-s", serial, "shell", "rm", "-f", remote], timeout: 15
                    )
                    return try UIHierarchyParser.parse(fetched.stdout)
                }
                lastError = fetched.stderr.isEmpty ? "empty UI XML" : fetched.stderr
            } else {
                lastError = dump.stderr.isEmpty ? "uiautomator dump failed" : dump.stderr
            }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        throw MotoMirrorError.parseFailure(lastError)
    }

    public func tap(serial: String, x: Int, y: Int) async throws {
        let serial = try validatedSerial(serial)
        guard (0...20_000).contains(x), (0...20_000).contains(y) else {
            throw MotoMirrorError.invalidInput("Tap coordinates are out of range.")
        }
        let output = try await run(
            ["-s", serial, "shell", "input", "tap", "\(x)", "\(y)"], timeout: 20
        )
        try output.requireSuccess("adb")
    }

    public func swipe(
        serial: String, x1: Int, y1: Int, x2: Int, y2: Int, durationMS: Int
    ) async throws {
        let serial = try validatedSerial(serial)
        guard [x1, y1, x2, y2].allSatisfy({ (0...20_000).contains($0) }),
              (0...10_000).contains(durationMS)
        else {
            throw MotoMirrorError.invalidInput("Swipe coordinates or duration are out of range.")
        }
        let output = try await run(
            ["-s", serial, "shell", "input", "swipe",
             "\(x1)", "\(y1)", "\(x2)", "\(y2)", "\(durationMS)"],
            timeout: 20
        )
        try output.requireSuccess("adb")
    }

    public func inputText(serial: String, text: String) async throws {
        let serial = try validatedSerial(serial)
        guard !text.isEmpty, text.count <= 2_000,
              !text.contains(where: { $0.isNewline || $0.asciiValue == 0 })
        else {
            throw MotoMirrorError.invalidInput("Text is empty, too long, or contains a newline.")
        }
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        let output = try await run(
            ["-s", serial, "shell", "input", "text", shellQuote(escaped)], timeout: 30
        )
        try output.requireSuccess("adb")
    }

    public func key(serial: String, key: String) async throws {
        let serial = try validatedSerial(serial)
        guard isValidKeyName(key) else {
            throw MotoMirrorError.invalidInput("Key must be a name such as HOME or KEYCODE_BACK.")
        }
        let output = try await run(
            ["-s", serial, "shell", "input", "keyevent", key], timeout: 20
        )
        try output.requireSuccess("adb")
    }

    // MARK: - Files and shell

    public func push(serial: String, local: String, remote: String) async throws -> String {
        let serial = try validatedSerial(serial)
        let localPath = (local as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: localPath) else {
            throw MotoMirrorError.invalidInput("Local file not found: \(localPath)")
        }
        let remotePath = try validatedRemotePath(remote)
        let output = try await run(
            ["-s", serial, "push", localPath, remotePath], timeout: 120
        )
        try output.requireSuccess("adb push")
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func pull(serial: String, remote: String, local: String) async throws -> String {
        let serial = try validatedSerial(serial)
        let remotePath = try validatedRemotePath(remote)
        let localPath = (local as NSString).expandingTildeInPath
        let directory = (localPath as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try? FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true
            )
        }
        let output = try await run(
            ["-s", serial, "pull", remotePath, localPath], timeout: 120
        )
        try output.requireSuccess("adb pull")
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func listFiles(serial: String, remote: String) async throws -> [String] {
        let serial = try validatedSerial(serial)
        let remotePath = try validatedRemotePath(remote)
        let output = try await run(
            ["-s", serial, "shell", "ls", "-1", remotePath], timeout: 30
        )
        try output.requireSuccess("adb")
        return output.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public func shell(
        serial: String, command: String, timeout: TimeInterval = 30
    ) async throws -> ProcessOutput {
        let serial = try validatedSerial(serial)
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MotoMirrorError.invalidInput("Shell command is empty.")
        }
        return try await run(
            ["-s", serial, "shell", command], timeout: max(1, min(timeout, 300))
        )
    }

    // MARK: - Device state

    public func wake(serial: String) async throws {
        try await key(serial: serial, key: "KEYCODE_WAKEUP")
    }

    public func sleep(serial: String) async throws {
        try await key(serial: serial, key: "KEYCODE_SLEEP")
    }

    public func rotate(serial: String, rotation: Int) async throws {
        let serial = try validatedSerial(serial)
        guard (0...3).contains(rotation) else {
            throw MotoMirrorError.invalidInput("Rotation must be 0, 1, 2, or 3.")
        }
        let output = try await run(
            ["-s", serial, "shell",
             "settings put system accelerometer_rotation 0; "
                + "settings put system user_rotation \(rotation)"],
            timeout: 20
        )
        try output.requireSuccess("adb")
    }

    public func volume(serial: String) async throws -> VolumeInfo {
        let serial = try validatedSerial(serial)
        let output = try await run(
            ["-s", serial, "shell", "cmd", "media_session", "volume", "--stream", "3", "--get"],
            timeout: 20
        )
        try output.requireSuccess("adb")
        guard let info = DeviceOutputParser.volume(output.stdout + output.stderr) else {
            throw MotoMirrorError.parseFailure("Could not read media volume.")
        }
        return info
    }

    public func setVolume(serial: String, level: Int) async throws {
        let serial = try validatedSerial(serial)
        let current = try await volume(serial: serial)
        guard (0...current.max).contains(level) else {
            throw MotoMirrorError.invalidInput("Volume must be between 0 and \(current.max).")
        }
        let output = try await run(
            ["-s", serial, "shell", "cmd", "media_session", "volume", "--stream", "3",
             "--set", "\(level)"],
            timeout: 20
        )
        try output.requireSuccess("adb")
    }

    public func logcat(serial: String, lines: Int) async throws -> String {
        let serial = try validatedSerial(serial)
        let count = max(1, min(lines, 5_000))
        let output = try await run(
            ["-s", serial, "logcat", "-d", "-t", "\(count)"], timeout: 60
        )
        try output.requireSuccess("adb")
        return output.stdout
    }

    public func waitForApp(serial: String, package: String, timeout: TimeInterval) async throws {
        let serial = try validatedSerial(serial)
        let package = try validatedPackage(package)
        let deadline = Date().addingTimeInterval(max(1, timeout))
        while Date() < deadline {
            if let current = try? await foregroundApp(serial: serial),
               current.package == package {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw MotoMirrorError.timeout(executable: "wait-for app \(package)")
    }

    // MARK: - Helpers

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        try await runner.run(adbURL, arguments: arguments, timeout: timeout)
    }

    private func validatedSerial(_ serial: String) throws -> String {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
            throw MotoMirrorError.invalidInput("The device serial is empty or malformed.")
        }
        return trimmed
    }

    private func validatedPackage(_ package: String) throws -> String {
        let trimmed = package.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !trimmed.isEmpty,
              trimmed.count <= 200,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw MotoMirrorError.invalidInput("Invalid Android package name: \(package)")
        }
        return trimmed
    }

    private func validatedRemotePath(_ remote: String) throws -> String {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isNewline || $0.asciiValue == 0 })
        else {
            throw MotoMirrorError.invalidInput("Invalid remote path.")
        }
        return trimmed
    }

    private func isValidKeyName(_ key: String) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.uppercaseLetters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || scalar == "_"
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
