import AppKit
import MotoMirrorCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: AppModel
    var presentedAsSheet = false

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    static let installCommand = "brew install scrcpy android-platform-tools"

    var body: some View {
        DetailScroll {
            VStack(alignment: .leading, spacing: 18) {
                header
                toolStatusCard
                installCard
                usbCard
                troubleshootingCard
                footer
            }
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMTheme.pagePadding)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MMTheme.orange.opacity(0.92), MMTheme.indigo.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .shadow(color: MMTheme.indigo.opacity(0.22), radius: 9, y: 3)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up MotoMirror")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("MotoMirror uses two free, open-source tools. Install them once, then connect with USB or Wi-Fi.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if presentedAsSheet {
                Button("Done") { dismiss() }
                    .buttonStyle(MMSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var toolStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Tool status",
                subtitle: model.toolsReady ? "Everything needed is installed" : "Install the missing tools below",
                icon: "checklist"
            )
            ToolStatusRow(
                name: "adb",
                detail: "Android Platform Tools",
                path: model.toolchain?.adb.path
            )
            ToolStatusRow(
                name: "scrcpy",
                detail: "Screen mirroring engine",
                path: model.toolchain?.scrcpy.path
            )
            if let ffmpeg = model.toolchain?.ffmpeg {
                ToolStatusRow(name: "ffmpeg", detail: "Recording helper", path: ffmpeg.path, optional: true)
            }
        }
        .mmCard(padding: 16)
    }

    private var installCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Install dependencies",
                subtitle: "Run this once in Terminal",
                icon: "terminal"
            )

            HStack(spacing: 10) {
                Text(Self.installCommand)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Button {
                    copyInstallCommand()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(MMSecondaryButtonStyle(tint: copied ? MMTheme.green : .primary))
                .help("Copy the install command")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("Homebrew is required. If brew is not installed, follow the one-line installer at brew.sh first.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MMTheme.indigo)
                Text("After installing, return here and click Check Again. MotoMirror finds tools in PATH, Homebrew, and the Android SDK automatically.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .mmCard(padding: 16)
    }

    private var usbCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(
                title: "Turn on USB debugging",
                subtitle: "One-time phone setup",
                icon: "cable.connector"
            )
            NumberedStep(
                number: 1,
                title: "Enable Developer options",
                detail: "Settings → About phone → tap Build number seven times.",
                icon: "gearshape"
            )
            NumberedStep(
                number: 2,
                title: "Enable USB debugging",
                detail: "Settings → System → Developer options → USB debugging on.",
                icon: "ladybug"
            )
            NumberedStep(
                number: 3,
                title: "Connect and authorize",
                detail: "Plug in a USB data cable. Unlock the phone and tap Allow on “Allow USB debugging?”.",
                icon: "checkmark.shield"
            )
        }
        .mmCard(padding: 16)
    }

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "Troubleshooting",
                subtitle: "The most common fixes",
                icon: "lifepreserver"
            )
            HelpRow(
                icon: "lock.shield",
                title: "The phone never shows the authorization prompt",
                detail: "Unlock the phone while the cable is connected. If needed, use Developer options → Revoke USB debugging authorizations, then reconnect."
            )
            HelpRow(
                icon: "cable.connector",
                title: "No devices found",
                detail: "Use a data cable, not a charge-only cable. Try another USB port directly on the Mac, then click Refresh."
            )
            HelpRow(
                icon: "wifi",
                title: "Wireless debugging disconnects",
                detail: "The pairing port changes every time Wireless debugging is turned off. Pair again from the Wireless… button. The connect port is usually 5555."
            )
            HelpRow(
                icon: "exclamationmark.magnifyingglass",
                title: "scrcpy still not found",
                detail: "Confirm brew install scrcpy android-platform-tools finished. In Settings → Tools you can point MotoMirror at a custom adb or scrcpy path."
            )
        }
        .mmCard(padding: 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.detectToolchain()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(MMPrimaryButtonStyle())

            Button {
                copyInstallCommand()
            } label: {
                Label(copied ? "Command Copied" : "Copy Install Command", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(MMSecondaryButtonStyle())

            Spacer()

            if presentedAsSheet {
                Button("Close") { dismiss() }
                    .buttonStyle(MMSecondaryButtonStyle())
            } else {
                Text(model.toolsReady ? "Tools are ready." : "Install the tools to continue.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyInstallCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.installCommand, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copied = false
        }
    }
}

private struct ToolStatusRow: View {
    let name: String
    let detail: String
    let path: String?
    var optional = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: path == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(path == nil ? MMTheme.orange : MMTheme.green)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if optional {
                        Text("optional")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }
                }
                Text(path ?? "Not found")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            StatusPill(
                text: path == nil ? "Missing" : "Found",
                tint: path == nil ? MMTheme.orange : MMTheme.green,
                compact: true
            )
        }
        .padding(.vertical, 5)
    }
}

private struct HelpRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MMTheme.indigo)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
