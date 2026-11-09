import Foundation

/// Talks to the `adb` binary through `ProcessRunner`. Every call is async so
/// the actor is never blocked by a synchronous `Process`.
public actor ADBClient: ADBServicing {
    private let adbURL: URL
    private let runner: ProcessRunner

    public init(adbURL: URL, runner: ProcessRunner = ProcessRunner()) {
        self.adbURL = adbURL
        self.runner = runner
    }

    // MARK: - ADBServicing

    public func version() async throws -> String {
        let output = try await run(["version"])
        try output.requireSuccess(executableName)

        let firstLine = output.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        guard let firstLine else {
            throw MotoMirrorError.parseFailure("adb version returned no output.")
        }
        return firstLine
    }

    public func devices() async throws -> [AndroidDevice] {
        let output = try await run(["devices", "-l"])
        try output.requireSuccess(executableName)
        return ADBParser.parseDevices(output.stdout)
    }

    public func details(for serial: String) async throws -> DeviceDetails {
        let serial = try validatedSerial(serial)
        var details = DeviceDetails(serial: serial)

        if let output = try? await run(["-s", serial, "shell", "getprop"]) {
            let properties = ADBParser.parseGetProp(output.stdout)
            details.manufacturer = nonEmpty(properties["ro.product.manufacturer"])
            details.model = nonEmpty(properties["ro.product.model"])
            details.androidVersion = nonEmpty(properties["ro.build.version.release"])
            details.sdk = nonEmpty(properties["ro.build.version.sdk"])
            details.abi = nonEmpty(properties["ro.product.cpu.abi"])
        }

        if let output = try? await run(["-s", serial, "shell", "dumpsys", "battery"]) {
            details.battery = ADBParser.parseBattery(output.stdout)
        }

        if let output = try? await run(["-s", serial, "shell", "df", "-k", "/data"]) {
            details.storage = ADBParser.parseStorage(output.stdout)
        }

        // One round trip for both screen properties; parseScreen understands the
        // combined text because each line keeps its own label.
        if let output = try? await run(["-s", serial, "shell", "wm size; wm density"]) {
            details.screen = ADBParser.parseScreen(output.stdout)
        }

        return details
    }

    public func screenshot(serial: String) async throws -> Data {
        let serial = try validatedSerial(serial)
        let output = try await runner.runData(
            adbURL,
            arguments: ["-s", serial, "exec-out", "screencap", "-p"],
            timeout: 20
        )

        guard output.status == 0 else {
            throw MotoMirrorError.commandFailed(
                executable: executableName,
                code: output.status,
                stderr: output.stderr
            )
        }

        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard !output.stdout.isEmpty else {
            throw MotoMirrorError.parseFailure("adb returned an empty screenshot.")
        }
        guard output.stdout.count >= pngMagic.count,
              Array(output.stdout.prefix(pngMagic.count)) == pngMagic else {
            throw MotoMirrorError.parseFailure("adb returned data that is not a PNG image.")
        }

        return output.stdout
    }

    public func pair(host: String, port: Int, code: String) async throws -> String {
        let address = try WirelessAddress(host: host, port: port)
        let pairingCode = try WirelessValidation.pairingCode(code)

        let output = try await run(["pair", address.hostPort, pairingCode], timeout: 60)
        let combined = combinedOutput(output)

        if combined.range(of: "successfully paired", options: .caseInsensitive) != nil {
            return combined.isEmpty ? "Successfully paired" : combined
        }

        if !output.succeeded {
            throw MotoMirrorError.commandFailed(
                executable: executableName,
                code: output.status,
                stderr: combined
            )
        }
        throw MotoMirrorError.invalidInput(
            combined.isEmpty ? "adb did not confirm pairing." : combined
        )
    }

    public func mdnsServices() async throws -> [ADBMDNSService] {
        let output = try await run(["mdns", "services"], timeout: 15)
        try output.requireSuccess(executableName)
        return ADBMDNSParser.parse(output.stdout)
    }

    public func connect(host: String, port: Int) async throws -> String {
        let address = try WirelessAddress(host: host, port: port)
        let output = try await run(["connect", address.hostPort])
        let combined = combinedOutput(output)
        let lowercased = combined.lowercased()

        if lowercased.contains("connected to") || lowercased.contains("already connected") {
            return combined
        }

        if !output.succeeded {
            throw MotoMirrorError.commandFailed(
                executable: executableName,
                code: output.status,
                stderr: combined
            )
        }
        throw MotoMirrorError.commandFailed(
            executable: executableName,
            code: output.status,
            stderr: combined.isEmpty ? "adb did not confirm the connection." : combined
        )
    }

    public func disconnect(host: String, port: Int) async throws {
        let address = try WirelessAddress(host: host, port: port)
        let output = try await run(["disconnect", address.hostPort], timeout: 15)
        if output.succeeded { return }

        let combined = combinedOutput(output)
        if combined.range(of: "no such device", options: .caseInsensitive) != nil {
            return
        }

        throw MotoMirrorError.commandFailed(
            executable: executableName,
            code: output.status,
            stderr: combined
        )
    }

    public func enableTCPIP(serial: String, port: Int) async throws {
        let serial = try validatedSerial(serial)
        guard (1...65535).contains(port) else {
            throw MotoMirrorError.invalidInput("Port must be between 1 and 65535.")
        }

        let output = try await run(["-s", serial, "tcpip", String(port)])
        let combined = combinedOutput(output)

        if combined.range(of: "restarting in tcp mode", options: .caseInsensitive) != nil {
            return
        }

        if !output.succeeded {
            throw MotoMirrorError.commandFailed(
                executable: executableName,
                code: output.status,
                stderr: combined
            )
        }
        throw MotoMirrorError.invalidInput(
            combined.isEmpty ? "adb did not switch the device to TCP mode." : combined
        )
    }

    public func sendKey(_ key: String, to serial: String) async throws {
        guard isValidKeyName(key) else {
            throw MotoMirrorError.invalidInput(
                "Key must be an Android key name such as HOME or KEYCODE_BACK."
            )
        }
        let serial = try validatedSerial(serial)

        let output = try await run(["-s", serial, "shell", "input", "keyevent", key], timeout: 15)
        try output.requireSuccess(executableName)
    }

    public func isReady(serial: String) async -> Bool {
        guard let devices = try? await devices() else { return false }
        return devices.contains { $0.serial == serial && $0.state == .device }
    }

    // MARK: - Helpers

    private var executableName: String {
        let name = adbURL.lastPathComponent
        return name.isEmpty ? "adb" : name
    }

    private func run(
        _ arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> ProcessOutput {
        try await runner.run(adbURL, arguments: arguments, timeout: timeout)
    }

    private func validatedSerial(_ serial: String) throws -> String {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
            throw MotoMirrorError.invalidInput("The device serial is empty or malformed.")
        }
        return trimmed
    }

    private func combinedOutput(_ output: ProcessOutput) -> String {
        let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty { return stderr }
        if stderr.isEmpty { return stdout }
        return stdout + "\n" + stderr
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func isValidKeyName(_ key: String) -> Bool {
        guard (1...40).contains(key.count) else { return false }
        return key.allSatisfy { character in
            character.isASCII && (character.isUppercase || character.isNumber || character == "_")
        }
    }
}
