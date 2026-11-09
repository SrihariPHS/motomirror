import Foundation

/// Fixed mirror profiles measured on a Moto G85. `custom` means the user has
/// taken over the individual `ScrcpyOptions` fields.
public enum MirrorPreset: String, CaseIterable, Codable, Sendable {
    /// Native-resolution capture fails on the Moto G85, so every concrete
    /// preset caps the long edge explicitly rather than asking for size 0.
    case quality
    case balanced
    case batterySaver
    case custom

    /// Concrete options for the fixed presets, and `nil` when the user is
    /// editing the options directly.
    public var options: ScrcpyOptions? {
        switch self {
        case .quality:
            return ScrcpyOptions(
                maxSize: 1920,
                videoBitRateMbps: 12,
                maxFPS: 60,
                audioEnabled: true,
                stayAwake: true,
                turnScreenOff: false
            )
        case .balanced:
            return ScrcpyOptions(
                maxSize: 1440,
                videoBitRateMbps: 8,
                maxFPS: 60,
                audioEnabled: true,
                stayAwake: true,
                turnScreenOff: false
            )
        case .batterySaver:
            return ScrcpyOptions(
                maxSize: 720,
                videoBitRateMbps: 4,
                maxFPS: 30,
                audioEnabled: false,
                stayAwake: true,
                turnScreenOff: true
            )
        case .custom:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .batterySaver: return "Battery saver"
        case .custom: return "Custom"
        }
    }

    public var subtitle: String {
        switch self {
        case .quality: return "1920 px · 12 Mbps · 60 fps · audio"
        case .balanced: return "1440 px · 8 Mbps · 60 fps · audio"
        case .batterySaver: return "720 px · 4 Mbps · 30 fps · no audio · screen off"
        case .custom: return "Use your own mirror options"
        }
    }

    public var batteryNote: String {
        switch self {
        case .quality:
            return "Sharpest text and video, with the highest phone battery draw."
        case .balanced:
            return "The everyday default: good detail with a steadier power draw."
        case .batterySaver:
            return "720p at 4 Mbps with no audio and the screen off drew about 430 mA on a Moto G85 in the benchmark."
        case .custom:
            return "Power use follows whatever options you choose."
        }
    }
}
