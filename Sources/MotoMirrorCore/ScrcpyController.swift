import Darwin
import Foundation

/// Long-lived scrcpy process controller.
///
/// Keeps the child process alive for the duration of a mirror session, streams
/// its output into a bounded log buffer, and guarantees the process is gone
/// after `stop()` or when the controller is released. All state is actor
/// isolated so callers can poll status and logs safely from any task.
public actor ScrcpyController: ScrcpyControlling {
    private static let maxLogLines = 2000
    private static let stopGracePeriod: TimeInterval = 3
    private static let killGracePeriod: TimeInterval = 1
    private static let pollInterval: TimeInterval = 0.02

    private let scrcpyURL: URL
    private let adbURL: URL?
    private let runner: ProcessRunner

    private var process: Process?
    private var readers: [PipeLineReader] = []
    private var currentStatus = ScrcpyStatus()
    private var logBuffer: [String] = []
    private var userRequestedStop = false

    public init(scrcpyURL: URL, adbURL: URL? = nil, runner: ProcessRunner = ProcessRunner()) {
        self.scrcpyURL = scrcpyURL
        self.adbURL = adbURL
        self.runner = runner
    }

    deinit {
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        let processReference = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if processReference.isRunning {
                Darwin.kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - ScrcpyControlling

    public func version() async throws -> String {
        let output = try await runner.run(
            scrcpyURL,
            arguments: ["--version"],
            timeout: 20,
            environment: childEnvironment()
        )
        try output.requireSuccess(scrcpyURL.lastPathComponent)

        for candidate in [output.stdout, output.stderr] {
            for line in candidate.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        throw MotoMirrorError.parseFailure("scrcpy --version produced no output.")
    }

    public func start(serial: String, options: ScrcpyOptions, recordPath: String?) async throws {
        // A start while a session is live is a restart, not a second process.
        if process != nil {
            await stop()
        }

        do {
            try ScrcpyCommand.validate(serial: serial, options: options)
        } catch {
            currentStatus = ScrcpyStatus(state: .failed, message: error.localizedDescription)
            throw error
        }

        let arguments = ScrcpyCommand.arguments(serial: serial, options: options, recordPath: recordPath)
        currentStatus = ScrcpyStatus(state: .starting)
        userRequestedStop = false

        let child = Process()
        child.executableURL = scrcpyURL
        child.arguments = arguments
        child.environment = childEnvironment()
        child.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe

        child.terminationHandler = { [weak self] finished in
            let exitCode = finished.terminationStatus
            Task { await self?.processDidTerminate(finished, exitCode: exitCode) }
        }

        do {
            try child.run()
        } catch {
            stdoutPipe.fileHandleForReading.closeFile()
            stderrPipe.fileHandleForReading.closeFile()
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
            let message = "Could not launch scrcpy: \(error.localizedDescription)"
            currentStatus = ScrcpyStatus(state: .failed, message: message)
            throw MotoMirrorError.commandFailed(
                executable: scrcpyURL.lastPathComponent,
                code: -1,
                stderr: error.localizedDescription
            )
        }

        // The child inherited its own copies of the write ends; close ours so
        // the readers see EOF when scrcpy exits.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        process = child
        currentStatus = ScrcpyStatus(
            state: .running,
            pid: child.processIdentifier,
            startedAt: Date()
        )

        let stdoutReader = PipeLineReader(handle: stdoutPipe.fileHandleForReading, name: "stdout") { [weak self] line in
            Task { await self?.appendLog(line) }
        }
        let stderrReader = PipeLineReader(handle: stderrPipe.fileHandleForReading, name: "stderr") { [weak self] line in
            Task { await self?.appendLog(line) }
        }
        readers = [stdoutReader, stderrReader]
        stdoutReader.start()
        stderrReader.start()
    }

    public func stop() async {
        guard let process else {
            if currentStatus.isActive {
                currentStatus = ScrcpyStatus(state: .stopped)
            }
            return
        }

        userRequestedStop = true
        currentStatus = ScrcpyStatus(
            state: .stopping,
            pid: process.processIdentifier,
            startedAt: currentStatus.startedAt
        )

        if process.isRunning {
            process.terminate()
        }

        let gracefulDeadline = Date().addingTimeInterval(Self.stopGracePeriod)
        while process.isRunning && Date() < gracefulDeadline {
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }

        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = Date().addingTimeInterval(Self.killGracePeriod)
            while process.isRunning && Date() < killDeadline {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            }
        }

        let exitCode: Int32? = process.isRunning ? nil : process.terminationStatus
        // The termination handler may have finished the cleanup while we slept.
        if self.process === process {
            self.process = nil
            readers.removeAll()
            currentStatus = ScrcpyStatus(
                state: .stopped,
                pid: process.processIdentifier,
                startedAt: currentStatus.startedAt,
                exitCode: exitCode
            )
        }
    }

    public func status() async -> ScrcpyStatus {
        currentStatus
    }

    public func logs() async -> [String] {
        logBuffer
    }

    public func clearLogs() async {
        logBuffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Private

    private func processDidTerminate(_ finished: Process, exitCode: Int32) {
        // Ignore stale handlers from a previous generation.
        guard process === finished else { return }

        process = nil
        readers.removeAll()

        if userRequestedStop || exitCode == 0 {
            currentStatus = ScrcpyStatus(
                state: .stopped,
                pid: finished.processIdentifier,
                startedAt: currentStatus.startedAt,
                exitCode: exitCode
            )
        } else {
            let detail = logBuffer.last(where: { !$0.isEmpty })
            let message = detail.map { "scrcpy exited with code \(exitCode): \($0)" }
                ?? "scrcpy exited with code \(exitCode)."
            currentStatus = ScrcpyStatus(
                state: .failed,
                pid: finished.processIdentifier,
                startedAt: currentStatus.startedAt,
                exitCode: exitCode,
                message: message
            )
        }
    }

    private func appendLog(_ line: String) {
        logBuffer.append(line)
        let overflow = logBuffer.count - Self.maxLogLines
        if overflow > 0 {
            logBuffer.removeFirst(overflow)
        }
    }

    private func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let adbURL {
            let adbDirectory = adbURL.deletingLastPathComponent().path
            let existingPath = environment["PATH"] ?? ""
            environment["PATH"] = existingPath.isEmpty ? adbDirectory : "\(adbDirectory):\(existingPath)"
            environment["ADB"] = adbURL.path
        }
        return environment
    }
}

/// Reads a pipe on a dedicated queue and emits complete lines. `availableData`
/// blocks until bytes arrive or the write end closes, so the reader exits as
/// soon as the child process terminates and never blocks the actor.
private final class PipeLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let queue: DispatchQueue
    private let onLine: @Sendable (String) -> Void
    private var buffer = Data()
    private var started = false

    init(handle: FileHandle, name: String, onLine: @escaping @Sendable (String) -> Void) {
        self.handle = handle
        self.queue = DispatchQueue(label: "com.motomirror.scrcpy.\(name)", qos: .utility)
        self.onLine = onLine
    }

    func start() {
        guard !started else { return }
        started = true
        queue.async { [weak self] in
            guard let self else { return }
            while true {
                let data = self.handle.availableData
                if data.isEmpty { break }
                self.consume(data)
            }
            self.flushRemainder()
            try? self.handle.close()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            emit(lineData)
        }
    }

    private func flushRemainder() {
        guard !buffer.isEmpty else { return }
        let lineData = buffer
        buffer.removeAll()
        emit(lineData)
    }

    private func emit(_ data: Data) {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onLine(line)
    }
}
