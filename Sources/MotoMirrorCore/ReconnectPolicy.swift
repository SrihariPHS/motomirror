import Foundation

/// Pure backoff and retry policy used when a mirror session drops and the
/// device is expected to come back. No I/O, no state, easy to test.
public struct ReconnectPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var baseDelaySeconds: TimeInterval
    public var maxDelaySeconds: TimeInterval

    public init(
        maxAttempts: Int = 10,
        baseDelaySeconds: TimeInterval = 1,
        maxDelaySeconds: TimeInterval = 30
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
    }

    /// Exponential backoff: attempt 1 waits `baseDelaySeconds`, attempt 2
    /// doubles it, and so on, capped at `maxDelaySeconds`. Attempts at or
    /// below zero mean "not attempted yet" and wait nothing.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let exponent = Double(attempt - 1)
        let raw = baseDelaySeconds * pow(2, exponent)
        guard raw.isFinite else { return max(0, maxDelaySeconds) }
        return max(0, min(maxDelaySeconds, raw))
    }

    /// Retrying is only useful while there is a device to attach to, the
    /// user still wants a session, and we have attempts left.
    public func shouldRetry(attempt: Int, devicePresent: Bool, userStopped: Bool) -> Bool {
        guard !userStopped, devicePresent else { return false }
        guard attempt >= 0 else { return false }
        return attempt < maxAttempts
    }
}
