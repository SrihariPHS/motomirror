import Foundation

public struct AndroidDevice: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable {
        case device
        case offline
        case unauthorized
        case authorizing
        case connecting
        case unknown
    }

    public enum Transport: String, Sendable {
        case usb
        case wireless
        case unknown
    }

    public let serial: String
    public var state: State
    public var model: String?
    public var product: String?
    public var device: String?
    public var transport: Transport

    public var id: String { serial }

    public var displayName: String {
        if let model, !model.isEmpty { return model.replacingOccurrences(of: "_", with: " ") }
        if let product, !product.isEmpty { return product.replacingOccurrences(of: "_", with: " ") }
        return serial
    }

    public var isUsable: Bool { state == .device }

    public init(
        serial: String,
        state: State,
        model: String? = nil,
        product: String? = nil,
        device: String? = nil,
        transport: Transport = .unknown
    ) {
        self.serial = serial
        self.state = state
        self.model = model
        self.product = product
        self.device = device
        self.transport = transport
    }
}

public struct BatteryInfo: Equatable, Sendable {
    public var level: Int?
    public var status: String?
    public var temperatureCelsius: Double?
    public var voltageMillivolts: Int?
    public var isCharging: Bool {
        guard let status else { return false }
        return status.caseInsensitiveCompare("Charging") == .orderedSame
            || status.caseInsensitiveCompare("Full") == .orderedSame
    }

    public init(level: Int? = nil, status: String? = nil, temperatureCelsius: Double? = nil, voltageMillivolts: Int? = nil) {
        self.level = level
        self.status = status
        self.temperatureCelsius = temperatureCelsius
        self.voltageMillivolts = voltageMillivolts
    }
}

public struct StorageInfo: Equatable, Sendable {
    public var totalBytes: Int64
    public var availableBytes: Int64

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

public struct ScreenInfo: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var density: Int?

    public init(width: Int, height: Int, density: Int? = nil) {
        self.width = width
        self.height = height
        self.density = density
    }
}

public struct DeviceDetails: Equatable, Sendable {
    public var serial: String
    public var manufacturer: String?
    public var model: String?
    public var androidVersion: String?
    public var sdk: String?
    public var abi: String?
    public var battery: BatteryInfo?
    public var storage: StorageInfo?
    public var screen: ScreenInfo?

    public init(
        serial: String,
        manufacturer: String? = nil,
        model: String? = nil,
        androidVersion: String? = nil,
        sdk: String? = nil,
        abi: String? = nil,
        battery: BatteryInfo? = nil,
        storage: StorageInfo? = nil,
        screen: ScreenInfo? = nil
    ) {
        self.serial = serial
        self.manufacturer = manufacturer
        self.model = model
        self.androidVersion = androidVersion
        self.sdk = sdk
        self.abi = abi
        self.battery = battery
        self.storage = storage
        self.screen = screen
    }
}

public struct Toolchain: Equatable, Sendable {
    public let adb: URL
    public let scrcpy: URL
    public let ffmpeg: URL?

    public init(adb: URL, scrcpy: URL, ffmpeg: URL?) {
        self.adb = adb
        self.scrcpy = scrcpy
        self.ffmpeg = ffmpeg
    }
}

public struct ScrcpyOptions: Codable, Equatable, Sendable {
    public var maxSize: Int
    public var videoBitRateMbps: Int
    public var maxFPS: Int
    public var audioEnabled: Bool
    public var stayAwake: Bool
    public var turnScreenOff: Bool
    public var showTouches: Bool
    public var alwaysOnTop: Bool
    public var fullscreen: Bool
    public var recordEnabled: Bool
    public var extraArguments: [String]

    public init(
        maxSize: Int = 0,
        videoBitRateMbps: Int = 8,
        maxFPS: Int = 60,
        audioEnabled: Bool = true,
        stayAwake: Bool = true,
        turnScreenOff: Bool = false,
        showTouches: Bool = false,
        alwaysOnTop: Bool = false,
        fullscreen: Bool = false,
        recordEnabled: Bool = false,
        extraArguments: [String] = []
    ) {
        self.maxSize = maxSize
        self.videoBitRateMbps = videoBitRateMbps
        self.maxFPS = maxFPS
        self.audioEnabled = audioEnabled
        self.stayAwake = stayAwake
        self.turnScreenOff = turnScreenOff
        self.showTouches = showTouches
        self.alwaysOnTop = alwaysOnTop
        self.fullscreen = fullscreen
        self.recordEnabled = recordEnabled
        self.extraArguments = extraArguments
    }

    public static let `default` = ScrcpyOptions()
}

public struct ScrcpyStatus: Equatable, Sendable {
    public enum State: String, Sendable {
        case idle
        case starting
        case running
        case stopping
        case stopped
        case failed
    }

    public var state: State
    public var pid: Int32?
    public var startedAt: Date?
    public var exitCode: Int32?
    public var message: String?

    public init(
        state: State = .idle,
        pid: Int32? = nil,
        startedAt: Date? = nil,
        exitCode: Int32? = nil,
        message: String? = nil
    ) {
        self.state = state
        self.pid = pid
        self.startedAt = startedAt
        self.exitCode = exitCode
        self.message = message
    }

    public var isActive: Bool { state == .starting || state == .running || state == .stopping }
}

public enum MotoMirrorError: LocalizedError, Equatable {
    case toolMissing(String)
    case commandFailed(executable: String, code: Int32, stderr: String)
    case timeout(executable: String)
    case invalidInput(String)
    case deviceNotFound(String)
    case deviceUnauthorized(String)
    case parseFailure(String)

    public var errorDescription: String? {
        switch self {
        case .toolMissing(let name):
            return "\(name) was not found. Install it with the setup script, then retry."
        case .commandFailed(let executable, let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(executable) exited with status \(code)."
                : "\(executable) exited with status \(code): \(detail)"
        case .timeout(let executable):
            return "\(executable) timed out."
        case .invalidInput(let message):
            return message
        case .deviceNotFound(let serial):
            return "Device \(serial) is not connected."
        case .deviceUnauthorized(let serial):
            return "Device \(serial) has not authorized this Mac. Accept the USB debugging prompt on the phone."
        case .parseFailure(let message):
            return "Could not read device output: \(message)"
        }
    }
}
