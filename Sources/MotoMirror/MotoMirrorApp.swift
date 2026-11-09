import AppKit
import MotoMirrorCore
import SwiftUI

@main
enum MotoMirrorLauncher {
    @MainActor
    static func main() {
        if SnapshotSupport.handleCommandLine() {
            exit(0)
        }
        MotoMirrorApp.main()
    }
}

struct MotoMirrorApp: App {
    @StateObject private var model: AppModel

    init() {
        let environment = ProcessInfo.processInfo.environment
        let demo = CommandLine.arguments.contains("--demo")
            || ["1", "true", "yes"].contains(environment["MOTOMIRROR_DEMO"]?.lowercased() ?? "")
        let autoMirror = CommandLine.arguments.contains("--auto-mirror")
            || ["1", "true", "yes"].contains(environment["MOTOMIRROR_AUTOSTART"]?.lowercased() ?? "")
        let preferredSerial = Self.launchValue(for: "--select-serial")
            ?? environment["MOTOMIRROR_SELECT_SERIAL"]
        let presetArgument = Self.launchValue(for: "--preset")

        let model = demo ? AppModel.demo() : AppModel.live()
        model.installSignalHandlers()
        model.preferInitialSerial(preferredSerial)
        if let launchPreset = Self.mirrorPreset(from: presetArgument) {
            model.preset = launchPreset
        }
        if autoMirror {
            model.enableAutoMirror()
        }
        _model = StateObject(wrappedValue: model)
    }

    private static func mirrorPreset(from raw: String?) -> MirrorPreset? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return nil
        }
        switch raw.replacingOccurrences(of: "_", with: "-") {
        case "quality": return .quality
        case "balanced": return .balanced
        case "battery-saver", "batterysaver": return .batterySaver
        default: return nil
        }
    }

    private static func launchValue(for flag: String) -> String? {
        let arguments = CommandLine.arguments
        var value: String?
        for (index, argument) in arguments.enumerated() {
            if argument == flag, index + 1 < arguments.count {
                value = arguments[index + 1]
            } else if argument.hasPrefix(flag + "=") {
                value = String(argument.dropFirst(flag.count + 1))
            }
        }
        return value
    }

    var body: some Scene {
        WindowGroup("MotoMirror") {
            ContentView(model: model)
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .background(WindowFitConfigurator())
                .onAppear {
                    model.start()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    model.shutdown()
                }
        }
        .defaultSize(width: 1180, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            MotoMirrorCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

struct MotoMirrorCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Device") {
            Button("Refresh Devices") {
                model.refreshNow()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.toolsReady)

            Divider()

            Button(model.isMirroring || model.isRecovering ? "Stop Mirroring" : "Start Mirroring") {
                model.toggleMirroring()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(
                model.status.state == .stopping
                    || (!model.isMirroring && !model.isRecovering && !model.canStartMirroring)
            )

            Button("Take Screenshot") {
                model.takeScreenshot()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!model.canUseSelectedDevice)

            Divider()

            Button("Wireless Pairing…") {
                model.isShowingWirelessSheet = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Setup & Help") {
                model.isShowingSetup = true
            }
        }

        CommandGroup(replacing: .help) {
            Button("MotoMirror Help") {
                model.isShowingSetup = true
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

/// Keeps the first window inside the visible screen area. macOS restores the
/// last window frame, which can leave the action bar off a short display.
struct WindowFitConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView.window)
        }
    }

    private func apply(to window: NSWindow?) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 14, dy: 10)
        var frame = window.frame
        let needsResize = frame.height > visible.height || frame.width > visible.width
        let offScreen = !visible.intersects(frame)
        guard needsResize || offScreen else { return }

        frame.size.width = min(max(frame.width, window.minSize.width), visible.width)
        frame.size.height = min(max(frame.height, window.minSize.height), visible.height)
        frame.origin.x = visible.midX - frame.size.width / 2
        frame.origin.y = visible.midY - frame.size.height / 2
        window.setFrame(frame, display: true)
    }
}
