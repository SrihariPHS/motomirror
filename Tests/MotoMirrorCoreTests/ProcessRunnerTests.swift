import XCTest
import MotoMirrorCore

final class ProcessRunnerTests: XCTestCase {
    private let runner = ProcessRunner()

    func testEchoesStdout() async throws {
        let output = try await runner.run(
            URL(fileURLWithPath: "/bin/echo"),
            arguments: ["mirror-ready"]
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertTrue(output.succeeded)
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "mirror-ready")
        XCTAssertTrue(output.stderr.isEmpty)
    }

    func testCapturesStderrAndNonzeroExit() async throws {
        let output = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo 'fatal: no device' >&2; exit 7"]
        )

        XCTAssertEqual(output.status, 7)
        XCTAssertFalse(output.succeeded)
        XCTAssertTrue(output.stderr.contains("fatal: no device"))
    }

    func testTimeoutTerminatesAndThrows() async throws {
        let started = Date()
        do {
            _ = try await runner.run(
                URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.3
            )
            XCTFail("Expected a timeout error")
        } catch let error as MotoMirrorError {
            guard case .timeout = error else {
                return XCTFail("Expected .timeout, got \(error)")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testArgumentsWithSpacesArePreserved() async throws {
        let output = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '<%s>' \"$1\"", "sh", "hello mirror world"]
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "<hello mirror world>")
    }
}
