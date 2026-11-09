import CoreGraphics
import Foundation
import ImageIO
import MotoMirrorCore
import UniformTypeIdentifiers

// MARK: - Scenarios

enum DemoScenario: String, CaseIterable, Sendable {
    case connected
    case empty
    case unauthorized
    case setup
}

// MARK: - Sample data

enum DemoData {
    static let phoneSerial = "ZY22DEMO85"
    static let wirelessSerial = "192.168.1.57:5555"

    static let motoG85 = AndroidDevice(
        serial: phoneSerial,
        state: .device,
        model: "Moto G85",
        product: "moto_g85",
        device: "moto_g85",
        transport: .usb
    )

    static let pixel8Pro = AndroidDevice(
        serial: wirelessSerial,
        state: .device,
        model: "Pixel 8 Pro",
        product: "husky",
        device: "husky",
        transport: .wireless
    )

    static let unauthorizedMoto = AndroidDevice(
        serial: phoneSerial,
        state: .unauthorized,
        model: "Moto G85",
        product: "moto_g85",
        device: "moto_g85",
        transport: .usb
    )

    static let motoDetails = DeviceDetails(
        serial: phoneSerial,
        manufacturer: "Motorola",
        model: "Moto G85",
        androidVersion: "15",
        sdk: "35",
        abi: "arm64-v8a",
        battery: BatteryInfo(
            level: 72,
            status: "Not charging",
            temperatureCelsius: 31.2,
            voltageMillivolts: 4176
        ),
        storage: StorageInfo(
            totalBytes: 256_000_000_000,
            availableBytes: 171_300_000_000
        ),
        screen: ScreenInfo(width: 1080, height: 2400, density: 400)
    )

    static let pixelDetails = DeviceDetails(
        serial: wirelessSerial,
        manufacturer: "Google",
        model: "Pixel 8 Pro",
        androidVersion: "14",
        sdk: "34",
        abi: "arm64-v8a",
        battery: BatteryInfo(
            level: 88,
            status: "Charging",
            temperatureCelsius: 28.6,
            voltageMillivolts: 4320
        ),
        storage: StorageInfo(
            totalBytes: 128_000_000_000,
            availableBytes: 61_200_000_000
        ),
        screen: ScreenInfo(width: 1344, height: 2992, density: 480)
    )
}

// MARK: - Demo ADB

final class DemoADBService: ADBServicing, @unchecked Sendable {
    private let scenario: DemoScenario
    private let lock = NSLock()
    private var storedDevices: [AndroidDevice]

    init(scenario: DemoScenario) {
        self.scenario = scenario
        switch scenario {
        case .connected:
            storedDevices = [DemoData.motoG85, DemoData.pixel8Pro]
        case .unauthorized:
            storedDevices = [DemoData.unauthorizedMoto]
        case .empty, .setup:
            storedDevices = []
        }
    }

    var previewDevices: [AndroidDevice] {
        withLock { storedDevices }
    }

    func previewDetails(for serial: String) -> DeviceDetails? {
        switch serial {
        case DemoData.phoneSerial: return DemoData.motoDetails
        case DemoData.wirelessSerial: return DemoData.pixelDetails
        default: return nil
        }
    }

    func version() async throws -> String {
        "Android Debug Bridge version 1.0.41"
    }

    func devices() async throws -> [AndroidDevice] {
        withLock { storedDevices }
    }

    func details(for serial: String) async throws -> DeviceDetails {
        let device = previewDevices.first { $0.serial == serial }
        guard let device else { throw MotoMirrorError.deviceNotFound(serial) }
        guard device.state != .unauthorized else {
            throw MotoMirrorError.deviceUnauthorized(serial)
        }
        if let details = previewDetails(for: serial) { return details }
        if serial.hasSuffix(":5555") {
            return DeviceDetails(
                serial: serial,
                manufacturer: "Motorola",
                model: "Moto G85",
                androidVersion: "15",
                sdk: "35",
                abi: "arm64-v8a",
                battery: BatteryInfo(level: 72, status: "Not charging", temperatureCelsius: 31.2),
                storage: StorageInfo(totalBytes: 256_000_000_000, availableBytes: 171_300_000_000),
                screen: ScreenInfo(width: 1080, height: 2400, density: 400)
            )
        }
        throw MotoMirrorError.deviceNotFound(serial)
    }

    func screenshot(serial: String) async throws -> Data {
        await awaitTask { DemoImage.pngData() }
    }

    func pair(host: String, port: Int, code: String) async throws -> String {
        await awaitTask { "Successfully paired to \(host):\(port)" }
    }

    func mdnsServices() async throws -> [ADBMDNSService] {
        [
            ADBMDNSService(
                name: "adb-demo-pairing",
                type: "_adb-tls-pairing._tcp",
                host: "192.168.1.55",
                port: 37001
            ),
            ADBMDNSService(
                name: "adb-demo-connect",
                type: "_adb-tls-connect._tcp",
                host: "192.168.1.55",
                port: 5555
            )
        ]
    }

    func connect(host: String, port: Int) async throws -> String {
        let serial = "\(host):\(port)"
        return withLock {
            if !storedDevices.contains(where: { $0.serial == serial }) {
                storedDevices.append(
                    AndroidDevice(
                        serial: serial,
                        state: .device,
                        model: "Moto G85",
                        product: "moto_g85",
                        device: "moto_g85",
                        transport: .wireless
                    )
                )
            }
            return "connected to \(serial)"
        }
    }

    func disconnect(host: String, port: Int) async throws {
        let serial = "\(host):\(port)"
        withLock {
            storedDevices.removeAll { $0.serial == serial }
        }
    }

    func enableTCPIP(serial: String, port: Int) async throws {}

    func sendKey(_ key: String, to serial: String) async throws {}

    func isReady(serial: String) async -> Bool {
        previewDevices.contains { $0.serial == serial && $0.state == .device }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Demo scrcpy

final class DemoScrcpyService: ScrcpyControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus = ScrcpyStatus()
    private var buffer: [String] = []

    func version() async throws -> String {
        "scrcpy 5.0.1 <https://github.com/Genymobile/scrcpy>"
    }

    func start(serial: String, options: ScrcpyOptions, recordPath: String?) async throws {
        withLock {
            let startDate = Date()
            currentStatus = ScrcpyStatus(
                state: .running,
                pid: 4821,
                startedAt: startDate
            )
            buffer.append("scrcpy 5.0.1 <https://github.com/Genymobile/scrcpy>")
            buffer.append("INFO: ADB device found: \(serial)")
            buffer.append("INFO: Device: \(DemoData.motoG85.model ?? "Moto G85") (Android 15)")
            buffer.append("INFO: Video: \(options.videoBitRateMbps) Mbps, \(options.maxFPS) fps")
            if !options.audioEnabled {
                buffer.append("INFO: Audio: disabled")
            }
            if let recordPath {
                buffer.append("INFO: Recording to \(recordPath)")
            }
            buffer.append("INFO: Renderer: metal")
            buffer.append("INFO: Texture: 1080x2400")
        }
    }

    func stop() async {
        withLock {
            if currentStatus.isActive {
                buffer.append("INFO: Stopping mirror session")
                currentStatus = ScrcpyStatus(
                    state: .stopped,
                    pid: currentStatus.pid,
                    startedAt: currentStatus.startedAt,
                    exitCode: 0
                )
            }
        }
    }

    func status() async -> ScrcpyStatus {
        withLock { currentStatus }
    }

    func logs() async -> [String] {
        withLock { buffer }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Demo screenshot

enum DemoImage {
    static func pngData() -> Data {
        let width = 540
        let height = 1200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return fallbackPNG
        }

        let colors = [
            CGColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1),
            CGColor(red: 0.18, green: 0.22, blue: 0.52, alpha: 1)
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: width, y: 0),
                options: []
            )
        }

        context.setFillColor(CGColor(red: 0.35, green: 0.38, blue: 0.86, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 190, y: 830, width: 160, height: 160))

        context.setFillColor(CGColor(red: 0.08, green: 0.58, blue: 0.58, alpha: 0.85))
        context.fillEllipse(in: CGRect(x: 150, y: 780, width: 240, height: 240))

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
        let card = CGPath(
            roundedRect: CGRect(x: 48, y: 250, width: 444, height: 430),
            cornerWidth: 30,
            cornerHeight: 30,
            transform: nil
        )
        context.addPath(card)
        context.fillPath()

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
        for index in 0..<3 {
            let bar = CGPath(
                roundedRect: CGRect(x: 88, y: 570 - CGFloat(index) * 54, width: 364, height: 24),
                cornerWidth: 12,
                cornerHeight: 12,
                transform: nil
            )
            context.addPath(bar)
            context.fillPath()
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        let pill = CGPath(
            roundedRect: CGRect(x: 176, y: 82, width: 188, height: 18),
            cornerWidth: 9,
            cornerHeight: 9,
            transform: nil
        )
        context.addPath(pill)
        context.fillPath()

        guard let image = context.makeImage() else { return fallbackPNG }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            return fallbackPNG
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return fallbackPNG }
        return data as Data
    }

    private static let fallbackPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    ) ?? Data()
}

private func awaitTask<T>(_ operation: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: operation())
        }
    }
}
