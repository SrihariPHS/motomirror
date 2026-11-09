import Darwin
import Foundation

public struct ProcessOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    @discardableResult
    public func requireSuccess(_ executable: String) throws -> ProcessOutput {
        guard succeeded else {
            throw MotoMirrorError.commandFailed(executable: executable, code: status, stderr: stderr)
        }
        return self
    }
}

public struct ProcessDataOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public init(status: Int32, stdout: Data, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        _ executable: URL,
        arguments: [String] = [],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) async throws -> ProcessOutput {
        let output = try await runData(
            executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        )
        return ProcessOutput(
            status: output.status,
            stdout: String(decoding: output.stdout, as: UTF8.self),
            stderr: output.stderr
        )
    }

    public func runData(
        _ executable: URL,
        arguments: [String] = [],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) async throws -> ProcessDataOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try Self.runSync(
                        executable,
                        arguments: arguments,
                        timeout: timeout,
                        environment: environment
                    )
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(
        _ executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]?
    ) throws -> ProcessDataOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutCapture = DataCapture()
        let stderrCapture = DataCapture()
        let readers = DispatchGroup()

        func startReaders() {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stdoutCapture.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stderrCapture.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
        }

        let timedOut = Flag()
        let deadline = max(0.1, timeout)
        let terminator = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.closeFile()
            stderrPipe.fileHandleForReading.closeFile()
            throw MotoMirrorError.commandFailed(
                executable: executable.lastPathComponent,
                code: -1,
                stderr: error.localizedDescription
            )
        }

        startReaders()
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: terminator)
        process.waitUntilExit()
        readers.wait()
        terminator.cancel()

        if timedOut.isSet {
            throw MotoMirrorError.timeout(executable: executable.lastPathComponent)
        }

        return ProcessDataOutput(
            status: process.terminationStatus,
            stdout: stdoutCapture.data,
            stderr: String(decoding: stderrCapture.data, as: UTF8.self)
        )
    }
}

private final class DataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
