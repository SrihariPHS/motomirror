import Darwin
import Foundation

/// Catches SIGTERM/SIGINT so a terminal `kill` still lets the app stop scrcpy
/// before exiting. Dispatch sources are created on a dedicated queue, and the
/// default signal action is ignored so the process does not die immediately.
final class TerminationSignalMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.motomirror.termination-signals",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []
    private var fired = false
    private let onSignal: @Sendable (Int32) -> Void

    init(onSignal: @escaping @Sendable (Int32) -> Void) {
        self.onSignal = onSignal
    }

    func install() {
        lock.lock()
        defer { lock.unlock() }
        guard sources.isEmpty else { return }

        for signalNumber in [SIGTERM, SIGINT] {
            _ = signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler { [weak self] in
                self?.fire(signalNumber)
            }
            source.resume()
            sources.append(source)
        }
    }

    private func fire(_ signalNumber: Int32) {
        lock.lock()
        guard !fired else {
            lock.unlock()
            return
        }
        fired = true
        lock.unlock()
        onSignal(signalNumber)
    }
}
