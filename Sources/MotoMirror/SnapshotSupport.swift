import AppKit
import SwiftUI

@MainActor
enum SnapshotSupport {
    static func handleCommandLine() -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.contains("--snapshot") || arguments.contains(where: { $0.hasPrefix("--snapshot=") }) else {
            return false
        }

        var path: String?
        var scenario = DemoScenario.connected
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--snapshot" {
                guard index + 1 < arguments.count else {
                    fail("--snapshot requires an output path, for example --snapshot /tmp/motomirror.png")
                }
                path = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--snapshot=") {
                path = String(argument.dropFirst("--snapshot=".count))
                index += 1
                continue
            }
            if argument == "--snapshot-state" {
                guard index + 1 < arguments.count else {
                    fail("--snapshot-state requires connected, empty, unauthorized, or setup.")
                }
                let value = arguments[index + 1].lowercased()
                guard let parsed = DemoScenario(rawValue: value) else {
                    fail("Unknown snapshot state “\(value)”. Use connected, empty, unauthorized, or setup.")
                }
                scenario = parsed
                index += 2
                continue
            }
            if argument.hasPrefix("--snapshot-state=") {
                let value = String(argument.dropFirst("--snapshot-state=".count)).lowercased()
                guard let parsed = DemoScenario(rawValue: value) else {
                    fail("Unknown snapshot state “\(value)”. Use connected, empty, unauthorized, or setup.")
                }
                scenario = parsed
                index += 1
                continue
            }
            index += 1
        }

        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("--snapshot requires an output path, for example --snapshot /tmp/motomirror.png")
        }

        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        render(scenario: scenario, to: path)
        return true
    }

    static func render(scenario: DemoScenario, to path: String) {
        let model = AppModel.demo(scenario: scenario)
        let width: CGFloat = 1280
        let height: CGFloat = 820
        let root = SnapshotRootView(model: model)
            .environment(\.mmSnapshotLayout, true)
            .frame(width: width, height: height)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: root)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: height)

        guard let cgImage = renderer.cgImage else {
            fail("ImageRenderer produced no image. Snapshot mode needs a graphical macOS session.")
        }

        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = NSSize(width: width, height: height)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            fail("Could not encode the rendered snapshot as PNG.")
        }

        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url, options: .atomic)
        } catch {
            fail("Could not write \(path): \(error.localizedDescription)")
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        print("MotoMirror snapshot: \(scenario.rawValue) → \(path) (\(pixelWidth)×\(pixelHeight), \(png.count) bytes)")
        fflush(stdout)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("MotoMirror: " + message + "\n").utf8))
        exit(2)
    }
}

/// Snapshot layout: the same sidebar and detail views as the live window, but
/// without `NavigationSplitView`, which `ImageRenderer` does not support.
struct SnapshotRootView: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SidebarView(model: model)
                .frame(width: 292, height: 820, alignment: .top)
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: 820)
            DetailContainer(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 1280, height: 820, alignment: .topLeading)
        .clipped()
        .tint(MMTheme.indigo)
        .background(MMTheme.pageFill)
    }
}
