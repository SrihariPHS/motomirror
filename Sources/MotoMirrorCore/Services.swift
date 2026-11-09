import Foundation

public protocol ADBServicing: Sendable {
    func version() async throws -> String
    func devices() async throws -> [AndroidDevice]
    func details(for serial: String) async throws -> DeviceDetails
    func screenshot(serial: String) async throws -> Data
    func pair(host: String, port: Int, code: String) async throws -> String
    func connect(host: String, port: Int) async throws -> String
    func mdnsServices() async throws -> [ADBMDNSService]
    func disconnect(host: String, port: Int) async throws
    func enableTCPIP(serial: String, port: Int) async throws
    func sendKey(_ key: String, to serial: String) async throws
    func isReady(serial: String) async -> Bool
}

public extension ADBServicing {
    func isReady(serial: String) async -> Bool {
        guard let devices = try? await devices() else { return false }
        return devices.contains { $0.serial == serial && $0.state == .device }
    }
}

public protocol ScrcpyControlling: Sendable {
    func version() async throws -> String
    func start(serial: String, options: ScrcpyOptions, recordPath: String?) async throws
    func stop() async
    func status() async -> ScrcpyStatus
    func logs() async -> [String]
}
