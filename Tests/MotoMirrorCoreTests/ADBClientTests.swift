import XCTest
@testable import MotoMirrorCore

final class ADBClientTests: XCTestCase {
    private let serial = "R5CX1234567"

    // MARK: - Version and devices

    func testVersionReturnsFirstNonEmptyLineAndPassesArguments() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "version") printf 'Android Debug Bridge version 1.0.41\\nVersion 37.0.2-1234567\\nInstalled as /opt/homebrew/bin/adb\\n';;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let version = try await client.version()

        XCTAssertEqual(version, "Android Debug Bridge version 1.0.41")
        XCTAssertEqual(fake.calls, ["[version]"])
    }

    func testDevicesParsesListAndUsesDashL() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "devices -l") printf 'List of devices attached\\nR5CX1234567\\tdevice product:moto_g85 model:moto_g85 device:g85 usb:1-4 transport_id:1\\n192.168.1.42:5555\\tunauthorized transport_id:2\\n';;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let devices = try await client.devices()

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].serial, "R5CX1234567")
        XCTAssertEqual(devices[0].state, .device)
        XCTAssertEqual(devices[0].transport, .usb)
        XCTAssertEqual(devices[1].state, .unauthorized)
        XCTAssertEqual(devices[1].transport, .wireless)
        XCTAssertEqual(fake.calls, ["[devices][-l]"])
    }

    func testDevicesThrowsCommandFailedOnNonzeroExit() async throws {
        let fake = try makeFakeADB("""
        printf 'error: no devices/emulators found\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.devices()
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed(let executable, let code, let stderr) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertEqual(executable, "adb")
            XCTAssertEqual(code, 1)
            XCTAssertTrue(stderr.contains("no devices"))
        }
    }

    // MARK: - Details

    func testDetailsReadsEveryDiagnostic() async throws {
        let fake = try makeFakeDetailsADB(batteryFails: false)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let details = try await client.details(for: serial)

        XCTAssertEqual(details.serial, serial)
        XCTAssertEqual(details.manufacturer, "motorola")
        XCTAssertEqual(details.model, "moto g85 5G")
        XCTAssertEqual(details.androidVersion, "14")
        XCTAssertEqual(details.sdk, "34")
        XCTAssertEqual(details.abi, "arm64-v8a")
        XCTAssertEqual(details.battery?.level, 85)
        XCTAssertEqual(details.battery?.temperatureCelsius, 31.0)
        XCTAssertEqual(details.storage?.totalBytes, 115343360 * 1024)
        XCTAssertEqual(details.screen, ScreenInfo(width: 720, height: 1600, density: 400))

        XCTAssertEqual(fake.calls.count, 1)
        let command = try XCTUnwrap(fake.calls.first)
        for marker in ["__PROPS__", "__BATTERY__", "__STORAGE__", "__SCREEN__"] {
            XCTAssertTrue(command.contains(marker), "batch command is missing \(marker)")
        }
    }

    func testDetailsSurvivesFailingOptionalCommand() async throws {
        let fake = try makeFakeDetailsADB(batteryFails: true)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let details = try await client.details(for: serial)

        XCTAssertEqual(details.model, "moto g85 5G")
        XCTAssertNil(details.battery)
        XCTAssertNotNil(details.storage)
        XCTAssertNotNil(details.screen)
    }

    func testDetailsReturnsWhatItReadWhenEverythingFails() async throws {
        let fake = try makeFakeADB("""
        printf 'error: device unauthorized\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let details = try await client.details(for: serial)

        XCTAssertEqual(details, DeviceDetails(serial: serial))
        XCTAssertEqual(fake.calls.count, 1)
    }

    func testDetailsRejectsEmptySerialWithoutCallingADB() async throws {
        let fake = try makeFakeADB("""
        printf 'should not run\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.details(for: "  ")
            XCTFail("expected invalidInput")
        } catch let error as MotoMirrorError {
            guard case .invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
        XCTAssertTrue(fake.calls.isEmpty)
    }

    // MARK: - Screenshot

    func testScreenshotAcceptsPNGMagicBytes() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "-s R5CX1234567 exec-out screencap -p") printf '\\x89PNG\\r\\n\\x1a\\nfake-image-payload';;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let data = try await client.screenshot(serial: serial)

        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(data.count, 8 + "fake-image-payload".utf8.count)
        XCTAssertEqual(fake.calls, ["[-s][R5CX1234567][exec-out][screencap][-p]"])
    }

    func testScreenshotRejectsNonPNGData() async throws {
        let fake = try makeFakeADB("""
        printf 'this is not a png'
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.screenshot(serial: serial)
            XCTFail("expected parseFailure")
        } catch let error as MotoMirrorError {
            guard case .parseFailure = error else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }

    func testScreenshotRejectsEmptyData() async throws {
        let fake = try makeFakeADB("""
        exit 0
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.screenshot(serial: serial)
            XCTFail("expected parseFailure")
        } catch let error as MotoMirrorError {
            guard case .parseFailure = error else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }

    func testScreenshotThrowsCommandFailedOnNonzeroExit() async throws {
        let fake = try makeFakeADB("""
        printf 'error: device offline\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.screenshot(serial: serial)
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed(_, 1, let stderr) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(stderr.contains("offline"))
        }
    }

    // MARK: - Pairing

    func testPairNormalizesCodeAndAcceptsSuccessOutput() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "pair 192.168.1.50:37123 123456") printf 'successfully PAIRED to 192.168.1.50:37123\\n';;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let message = try await client.pair(host: "192.168.1.50", port: 37123, code: " 123-456 ")

        XCTAssertTrue(message.lowercased().contains("successfully paired"))
        XCTAssertEqual(fake.calls, ["[pair][192.168.1.50:37123][123456]"])
    }

    func testPairFailureSurfacesADBMessage() async throws {
        let fake = try makeFakeADB("""
        printf 'Failed: Wrong password or connection was dropped.\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.pair(host: "192.168.1.50", port: 37123, code: "123456")
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed(_, 1, let stderr) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(stderr.contains("Wrong password"))
        }
    }

    func testPairRejectsInvalidCodeBeforeRunningADB() async throws {
        let fake = try makeFakeADB("""
        printf 'should not run\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.pair(host: "192.168.1.50", port: 37123, code: "12345")
            XCTFail("expected invalidInput")
        } catch let error as MotoMirrorError {
            guard case .invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testPairRejectsInvalidHostBeforeRunningADB() async throws {
        let fake = try makeFakeADB("""
        printf 'should not run\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.pair(host: "192.168.1.50; reboot", port: 37123, code: "123456")
            XCTFail("expected invalidInput")
        } catch let error as MotoMirrorError {
            guard case .invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
        XCTAssertTrue(fake.calls.isEmpty)
    }

    // MARK: - Connect and disconnect

    func testConnectAcceptsConnectedToOutput() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "connect 192.168.1.50:5555") printf 'connected to 192.168.1.50:5555\\n';;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let message = try await client.connect(host: "192.168.1.50", port: 5555)

        XCTAssertTrue(message.contains("connected to"))
        XCTAssertEqual(fake.calls, ["[connect][192.168.1.50:5555]"])
    }

    func testConnectAcceptsAlreadyConnectedOutput() async throws {
        let fake = try makeFakeADB("""
        printf 'already connected to 192.168.1.50:5555\\n'
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let message = try await client.connect(host: "192.168.1.50", port: 5555)

        XCTAssertTrue(message.contains("already connected"))
    }

    func testConnectFailureThrowsWithADBOutput() async throws {
        let fake = try makeFakeADB("""
        printf "failed to connect to '192.168.1.50:5555': Connection refused\\n" >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            _ = try await client.connect(host: "192.168.1.50", port: 5555)
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed(_, 1, let stderr) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertTrue(stderr.contains("Connection refused"))
        }
    }

    func testDisconnectToleratesNoSuchDevice() async throws {
        let fake = try makeFakeADB("""
        printf 'error: no such device: 192.168.1.50:5555\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        try await client.disconnect(host: "192.168.1.50", port: 5555)

        XCTAssertEqual(fake.calls, ["[disconnect][192.168.1.50:5555]"])
    }

    func testDisconnectFailureThrows() async throws {
        let fake = try makeFakeADB("""
        printf 'error: protocol fault\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            try await client.disconnect(host: "192.168.1.50", port: 5555)
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
        }
    }

    // MARK: - TCP/IP and key events

    func testEnableTCPIPAcceptsRestartingOutput() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "-s R5CX1234567 tcpip 5555") printf 'restarting in TCP mode port: 5555\\n';;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        try await client.enableTCPIP(serial: serial, port: 5555)

        XCTAssertEqual(fake.calls, ["[-s][R5CX1234567][tcpip][5555]"])
    }

    func testEnableTCPIPFailureThrowsCommandFailed() async throws {
        let fake = try makeFakeADB("""
        printf "error: device 'R5CX1234567' not found\\n" >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            try await client.enableTCPIP(serial: serial, port: 5555)
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
        }
    }

    func testSendKeyPassesKeyeventArguments() async throws {
        let fake = try makeFakeADB("""
        case "$*" in
          "-s R5CX1234567 shell input keyevent KEYCODE_HOME") exit 0;;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        try await client.sendKey("KEYCODE_HOME", to: serial)

        XCTAssertEqual(fake.calls, ["[-s][R5CX1234567][shell][input][keyevent][KEYCODE_HOME]"])
    }

    func testSendKeyRejectsInvalidKeyBeforeRunningADB() async throws {
        let fake = try makeFakeADB("""
        printf 'should not run\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let invalidKeys = ["home", "KEY CODE", "KEY-CODE", "", String(repeating: "A", count: 41)]

        for key in invalidKeys {
            do {
                try await client.sendKey(key, to: serial)
                XCTFail("expected invalidInput for \(key)")
            } catch let error as MotoMirrorError {
                guard case .invalidInput = error else {
                    return XCTFail("expected invalidInput for \(key), got \(error)")
                }
            }
        }
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testSendKeyFailureThrows() async throws {
        let fake = try makeFakeADB("""
        printf 'error: device not found\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        do {
            try await client.sendKey("HOME", to: serial)
            XCTFail("expected commandFailed")
        } catch let error as MotoMirrorError {
            guard case .commandFailed = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
        }
    }

    // MARK: - Readiness

    func testIsReadyTrueOnlyForAuthorizedDevice() async throws {
        let fake = try makeFakeADB("""
        printf 'List of devices attached\\nR5CX1234567\\tdevice usb:1-4 transport_id:1\\nZY22OTHER\\tunauthorized usb:1-2 transport_id:2\\n'
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)

        let ready = await client.isReady(serial: serial)
        let otherReady = await client.isReady(serial: "ZY22OTHER")
        let missingReady = await client.isReady(serial: "NOPE")

        XCTAssertTrue(ready)
        XCTAssertFalse(otherReady)
        XCTAssertFalse(missingReady)
    }

    func testIsReadyReturnsFalseWhenDevicesFails() async throws {
        let fake = try makeFakeADB("""
        printf 'error: adb server is out of date\\n' >&2
        exit 1
        """)
        defer { fake.cleanup() }

        let client = ADBClient(adbURL: fake.executable)
        let ready = await client.isReady(serial: serial)

        XCTAssertFalse(ready)
    }

    // MARK: - Helpers

    private struct FakeADB {
        let directory: URL
        let executable: URL
        let logURL: URL

        var calls: [String] {
            guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
            return text.split(whereSeparator: \.isNewline).map(String.init)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFakeADB(_ body: String) throws -> FakeADB {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("motomirror-adb-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let logURL = directory.appendingPathComponent("calls.log")
        try Data().write(to: logURL)

        let executable = directory.appendingPathComponent("adb")
        let script = """
        #!/bin/sh
        for arg in "$@"; do printf '[%s]' "$arg" >> '\(logURL.path)'; done
        printf '\\n' >> '\(logURL.path)'
        \(body)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        return FakeADB(directory: directory, executable: executable, logURL: logURL)
    }

    private func makeFakeDetailsADB(batteryFails: Bool) throws -> FakeADB {
        let batteryOutput = batteryFails
            ? "printf '__BATTERY__\\nerror: battery service unavailable\\n';"
            : "printf '__BATTERY__\\nCurrent Battery Service state:\\n  level: 85\\n  status: 2\\n  temperature: 310\\n  voltage: 4200\\n';"

        return try makeFakeADB("""
        case "$*" in
          *__PROPS__*)
            printf '__PROPS__\\n[ro.product.manufacturer]: [motorola]\\n[ro.product.model]: [moto g85 5G]\\n[ro.build.version.release]: [14]\\n[ro.build.version.sdk]: [34]\\n[ro.product.cpu.abi]: [arm64-v8a]\\n'
            \(batteryOutput)
            printf '__STORAGE__\\nFilesystem 1K-blocks Used Available Use%% Mounted on\\n/dev/block/dm-6 115343360 45678900 69664460 40%% /data\\n'
            printf '__SCREEN__\\nPhysical size: 1080x2400\\nOverride size: 720x1600\\nPhysical density: 420\\nOverride density: 400\\n'
            \(batteryFails ? "exit 1" : "exit 0")
            ;;
          *) printf 'unexpected command: %s\\n' "$*" >&2; exit 1;;
        esac
        """)
    }
}
