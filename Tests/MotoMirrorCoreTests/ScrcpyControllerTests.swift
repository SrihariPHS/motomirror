import Darwin
import XCTest
import MotoMirrorCore

final class ScrcpyControllerTests: XCTestCase {
    // MARK: - Version

    func testVersionReturnsFirstNonEmptyLine() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo ""
          echo "scrcpy 5.0.1"
          echo "second line"
          exit 0
        fi
        echo "start should not be called"
        exit 1
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        let version = try await controller.version()

        XCTAssertEqual(version, "scrcpy 5.0.1")
    }

    // MARK: - Lifecycle

    func testStartReachesRunningStreamsLogsAndStopReturnsToStopped() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "fake scrcpy booting"
        echo "warning: simulated stderr" >&2
        exec sleep 2
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        let initial = await controller.status()
        XCTAssertEqual(initial.state, .idle)

        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)
        let running = await controller.status()
        XCTAssertEqual(running.state, .running)
        XCTAssertNotNil(running.pid)
        XCTAssertNotNil(running.startedAt)

        let sawStdout = await waitUntil {
            await controller.logs().contains { $0.contains("fake scrcpy booting") }
        }
        let sawStderr = await waitUntil {
            await controller.logs().contains { $0.contains("warning: simulated stderr") }
        }
        XCTAssertTrue(sawStdout, "stdout line should reach the log buffer")
        XCTAssertTrue(sawStderr, "stderr line should reach the log buffer")

        await controller.clearLogs()
        let cleared = await controller.logs()
        XCTAssertTrue(cleared.isEmpty)

        await controller.stop()
        let stopped = await controller.status()
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(stopped.exitCode, 15, "sleep should exit via SIGTERM")

        // Stopping an idle controller must be harmless.
        await controller.stop()
        let stoppedAgain = await controller.status()
        XCTAssertEqual(stoppedAgain.state, .stopped)
    }

    func testSecondStartRestartsInsteadOfLeaking() async throws {
        let fake = try FakeScrcpy(body: "")
        defer { fake.destroy() }

        let pidFile = fake.directory.appendingPathComponent("pids.txt").path
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "$$" >> "\(pidFile)"
        echo "fake scrcpy ready"
        exec sleep 2
        """.write(to: fake.executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.executable.path)

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)
        let firstPIDs = await waitForPIDs(in: pidFile, count: 1)
        XCTAssertEqual(firstPIDs.count, 1)
        guard let firstPID = firstPIDs.first else { return }

        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)
        let secondPIDs = await waitForPIDs(in: pidFile, count: 2)
        XCTAssertEqual(secondPIDs.count, 2)
        guard secondPIDs.count == 2 else { return }

        let runningPID = await controller.status().pid
        XCTAssertNotEqual(secondPIDs[0], secondPIDs[1], "a restart must spawn a new process")
        XCTAssertEqual(runningPID, secondPIDs[1])

        let firstIsGone = await waitUntil(timeout: 3) {
            Darwin.kill(firstPID, 0) == -1
        }
        XCTAssertTrue(firstIsGone, "the first scrcpy process must not be leaked")

        await controller.stop()
        let stoppedAfterRestart = await controller.status()
        XCTAssertEqual(stoppedAfterRestart.state, .stopped)
    }

    func testNaturalZeroExitBecomesStoppedWithExitCode() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "clean exit"
        exit 0
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)

        let becameStopped = await waitUntil {
            await controller.status().state == .stopped
        }
        XCTAssertTrue(becameStopped)
        let status = await controller.status()
        XCTAssertEqual(status.state, .stopped)
        XCTAssertEqual(status.exitCode, 0)
    }

    func testNaturalNonzeroExitBecomesFailed() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "fatal: simulated device loss" >&2
        exit 3
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)

        let failed = await waitUntil {
            await controller.status().state == .failed
        }
        XCTAssertTrue(failed)
        let status = await controller.status()
        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.exitCode, 3)
        XCTAssertNotNil(status.message)
        XCTAssertTrue(status.message?.contains("3") ?? false)
    }

    func testInvalidInputFailsLocallyWithoutLaunching() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "should not run"
        exit 0
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        do {
            try await controller.start(serial: "bad serial", options: .default, recordPath: nil)
            XCTFail("Expected validation to throw")
        } catch let error as MotoMirrorError {
            guard case .invalidInput = error else {
                return XCTFail("Expected .invalidInput, got \(error)")
            }
        }

        let status = await controller.status()
        XCTAssertEqual(status.state, .failed)
        XCTAssertNotNil(status.message)
        XCTAssertNil(status.pid)
    }

    func testLaunchFailureLeavesFailedStatusAndThrows() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-scrcpy-\(UUID().uuidString)")
        let controller = ScrcpyController(scrcpyURL: missing)

        do {
            try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)
            XCTFail("Expected launch to throw")
        } catch let error as MotoMirrorError {
            guard case .commandFailed = error else {
                return XCTFail("Expected .commandFailed, got \(error)")
            }
        }

        let status = await controller.status()
        XCTAssertEqual(status.state, .failed)
        XCTAssertNotNil(status.message)
        XCTAssertTrue(status.message?.contains("Could not launch scrcpy") ?? false)
    }

    func testStopEscalatesToSIGKILLWhenProcessIgnoresTerminate() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        trap '' TERM
        echo "stubborn scrcpy ready"
        exec sleep 30
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)
        let sawBanner = await waitUntil {
            await controller.logs().contains { $0.contains("stubborn scrcpy ready") }
        }
        XCTAssertTrue(sawBanner)

        let started = Date()
        await controller.stop()
        let elapsed = Date().timeIntervalSince(started)

        let status = await controller.status()
        XCTAssertEqual(status.state, .stopped)
        XCTAssertEqual(status.exitCode, SIGKILL)
        XCTAssertGreaterThanOrEqual(elapsed, 2.5, "stop should wait its grace period before SIGKILL")
        XCTAssertLessThan(elapsed, 6)
    }

    func testDeinitCleansUpLiveProcess() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "deinit scrcpy ready"
        exec sleep 30
        """)
        defer { fake.destroy() }

        var controller: ScrcpyController? = ScrcpyController(scrcpyURL: fake.executable)
        try await controller?.start(serial: "ZY22ABC", options: .default, recordPath: nil)
        let pid = await controller?.status().pid
        XCTAssertNotNil(pid)

        controller = nil

        guard let pid else { return }
        let gone = await waitUntil(timeout: 5) {
            Darwin.kill(pid, 0) == -1
        }
        XCTAssertTrue(gone, "releasing the controller must terminate scrcpy")
    }

    func testLogBufferIsBoundedAndDropsOldestLines() async throws {
        let fake = try FakeScrcpy(body: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        i=1
        while [ $i -le 2050 ]; do
          echo "line $i"
          i=$((i+1))
        done
        sleep 0.2
        echo "marker-done"
        exec sleep 5
        """)
        defer { fake.destroy() }

        let controller = ScrcpyController(scrcpyURL: fake.executable)
        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)

        let observedMarker = await waitUntil(timeout: 10) {
            await controller.logs().last == "marker-done"
        }
        XCTAssertTrue(observedMarker)
        let logs = await controller.logs()
        XCTAssertEqual(logs.count, 2000, "the log buffer must cap at 2000 lines")
        XCTAssertEqual(logs.last, "marker-done")

        await controller.stop()
    }

    func testEnvironmentExposesADBAndPrependsItsDirectoryToPATH() async throws {
        let fake = try FakeScrcpy(body: "")
        defer { fake.destroy() }

        let adbDirectory = fake.directory.appendingPathComponent("platform-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: adbDirectory, withIntermediateDirectories: true)
        let adbURL = adbDirectory.appendingPathComponent("adb")
        try "#!/bin/sh\nexit 0\n".write(to: adbURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adbURL.path)

        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "scrcpy 5.0.1"
          exit 0
        fi
        echo "ADB=$ADB"
        echo "PATH=$PATH"
        exec sleep 2
        """.write(to: fake.executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.executable.path)

        let controller = ScrcpyController(scrcpyURL: fake.executable, adbURL: adbURL)
        try await controller.start(serial: "ZY22ABC", options: .default, recordPath: nil)

        let sawADB = await waitUntil {
            await controller.logs().contains { $0 == "ADB=\(adbURL.path)" }
        }
        let sawPath = await waitUntil {
            await controller.logs().contains { line in
                line.hasPrefix("PATH=\(adbDirectory.path):")
            }
        }
        XCTAssertTrue(sawADB)
        XCTAssertTrue(sawPath)

        await controller.stop()
    }
}

// MARK: - ReconnectPolicy tests

final class ReconnectPolicyTests: XCTestCase {
    func testDefaultPolicyValues() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.maxAttempts, 10)
        XCTAssertEqual(policy.baseDelaySeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(policy.maxDelaySeconds, 30, accuracy: 0.0001)
    }

    func testBackoffDoublesAndCapsAtMaxDelay() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.delay(forAttempt: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 2), 2, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 3), 4, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 4), 8, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 5), 16, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 6), 30, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 10), 30, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 100), 30, accuracy: 0.0001)
    }

    func testCustomBaseDelayAndCap() {
        let policy = ReconnectPolicy(maxAttempts: 5, baseDelaySeconds: 0.5, maxDelaySeconds: 3)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 2), 1, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 3), 2, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 4), 3, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 8), 3, accuracy: 0.0001)
    }

    func testNonPositiveAttemptWaitsNothing() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.delay(forAttempt: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: -4), 0, accuracy: 0.0001)
    }

    func testUserStopDisablesRetry() {
        let policy = ReconnectPolicy()
        XCTAssertFalse(policy.shouldRetry(attempt: 0, devicePresent: true, userStopped: true))
        XCTAssertFalse(policy.shouldRetry(attempt: 1, devicePresent: false, userStopped: true))
    }

    func testDeviceAbsentDisablesRetry() {
        let policy = ReconnectPolicy()
        XCTAssertFalse(policy.shouldRetry(attempt: 0, devicePresent: false, userStopped: false))
    }

    func testAttemptCapStopsRetrying() {
        let policy = ReconnectPolicy(maxAttempts: 3)
        XCTAssertTrue(policy.shouldRetry(attempt: 0, devicePresent: true, userStopped: false))
        XCTAssertTrue(policy.shouldRetry(attempt: 1, devicePresent: true, userStopped: false))
        XCTAssertTrue(policy.shouldRetry(attempt: 2, devicePresent: true, userStopped: false))
        XCTAssertFalse(policy.shouldRetry(attempt: 3, devicePresent: true, userStopped: false))
        XCTAssertFalse(policy.shouldRetry(attempt: 9, devicePresent: true, userStopped: false))
    }

    func testDefaultPolicyRetriesThroughSevenSecondReplugWindow() {
        let policy = ReconnectPolicy()
        // Cumulative delay before attempt 6 is 1+2+4+8+16 = 31s, so a
        // phone that takes 10-30s to come back is still attempted.
        for attempt in 0..<10 {
            XCTAssertTrue(
                policy.shouldRetry(attempt: attempt, devicePresent: true, userStopped: false),
                "attempt \(attempt) should still retry"
            )
        }
        XCTAssertFalse(policy.shouldRetry(attempt: 10, devicePresent: true, userStopped: false))
        XCTAssertFalse(policy.shouldRetry(attempt: 11, devicePresent: true, userStopped: false))
    }

    func testZeroAttemptsNeverRetries() {
        let policy = ReconnectPolicy(maxAttempts: 0)
        XCTAssertFalse(policy.shouldRetry(attempt: 0, devicePresent: true, userStopped: false))
    }
}

// MARK: - Test helpers

private struct FakeScrcpy {
    let directory: URL
    let executable: URL

    init(body: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotoMirrorFakeScrcpy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("scrcpy")
        if body.isEmpty {
            // The caller writes the real script after preparing side files.
            try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        } else {
            try body.write(to: executable, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func destroy() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func waitUntil(
    timeout: TimeInterval = 5,
    interval: TimeInterval = 0.02,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
    return await condition()
}

private func waitForPIDs(in path: String, count: Int, timeout: TimeInterval = 5) async -> [Int32] {
    _ = await waitUntil(timeout: timeout) {
        readPIDs(in: path).count >= count
    }
    return readPIDs(in: path)
}

private func readPIDs(in path: String) -> [Int32] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return text.split(whereSeparator: \.isNewline).compactMap { Int32(String($0).trimmingCharacters(in: .whitespaces)) }
}
