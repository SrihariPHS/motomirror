import AppKit
import MotoMirrorCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var adbPath: String
    @State private var scrcpyPath: String
    @State private var showResetConfirmation = false
    @State private var savedPulse = false

    init() {
        let defaults = UserDefaults.standard
        _adbPath = State(initialValue: defaults.string(forKey: MMDefaults.adbPath) ?? "")
        _scrcpyPath = State(initialValue: defaults.string(forKey: MMDefaults.scrcpyPath) ?? "")
    }

    var body: some View {
        TabView {
            toolsTab
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            defaultsTab
                .tabItem { Label("Mirroring", systemImage: "slider.horizontal.3") }
            recordingTab
                .tabItem { Label("Recording", systemImage: "record.circle") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 470)
        .tint(MMTheme.indigo)
        .alert("Reset all settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetEverything()
            }
        } message: {
            Text("Tool paths, mirror options, and the recording folder return to their defaults. Recorded files are not deleted.")
        }
    }

    // MARK: - Tools

    private var toolsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(
                    title: "Tool locations",
                    subtitle: "Leave a field empty to detect the tool automatically",
                    icon: "wrench.and.screwdriver"
                ) {
                    SettingsField(
                        label: "adb path",
                        placeholder: "Auto-detect — /opt/homebrew/bin/adb",
                        text: $adbPath
                    )
                    SettingsField(
                        label: "scrcpy path",
                        placeholder: "Auto-detect — /opt/homebrew/bin/scrcpy",
                        text: $scrcpyPath
                    )

                    HStack(spacing: 9) {
                        Button {
                            model.applyToolPaths(adbPath: adbPath, scrcpyPath: scrcpyPath)
                            flashSaved()
                        } label: {
                            Label(savedPulse ? "Saved" : "Save & Check", systemImage: savedPulse ? "checkmark" : "checkmark.circle")
                        }
                        .buttonStyle(MMPrimaryButtonStyle())
                        .disabled(model.status.isActive)

                        Button("Use Automatic Detection") {
                            adbPath = ""
                            scrcpyPath = ""
                            model.applyToolPaths(adbPath: "", scrcpyPath: "")
                            flashSaved()
                        }
                        .buttonStyle(MMSecondaryButtonStyle())
                        .disabled(model.status.isActive)

                        Spacer()
                    }

                    Text("MotoMirror searches PATH, Homebrew (/opt/homebrew/bin, /usr/local/bin), and the Android SDK platform-tools folder. Changes apply immediately.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(
                    title: "Current tools",
                    subtitle: model.toolsReady ? "Ready to mirror" : "One or both tools are missing",
                    icon: model.toolsReady ? "checkmark.seal" : "exclamationmark.triangle"
                ) {
                    SettingsToolRow(
                        name: "adb",
                        path: model.toolchain?.adb.path
                    )
                    SettingsToolRow(
                        name: "scrcpy",
                        path: model.toolchain?.scrcpy.path
                    )
                    if let summary = model.toolVersionSummary {
                        Text(summary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if !model.toolsReady {
                    SettingsSection(
                        title: "Install with Homebrew",
                        subtitle: "Run this in Terminal",
                        icon: "terminal"
                    ) {
                        Text(SetupView.installCommand)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.045))
                            )
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(SetupView.installCommand, forType: .string)
                        } label: {
                            Label("Copy Command", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(MMSecondaryButtonStyle())
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Defaults

    private var defaultsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Default mirror options")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Saved automatically and used for every new mirror session.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)

                OptionsView(model: model, showsHeader: false)
                    .mmCard(padding: 16)

                Text("Changing options while mirroring is disabled. Stop the session to unlock them.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(20)
        }
    }

    // MARK: - Recording

    private var recordingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(
                    title: "Recording folder",
                    subtitle: "Timestamped MP4 files are saved here",
                    icon: "folder"
                ) {
                    HStack(spacing: 8) {
                        TextField(
                            "~/Movies/MotoMirror",
                            text: Binding(
                                get: { model.recordingFolder },
                                set: { model.setRecordingFolder($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(model.status.isActive)

                        Button("Choose…") {
                            chooseRecordingFolder()
                        }
                        .buttonStyle(MMSecondaryButtonStyle())
                        .disabled(model.status.isActive)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(MMTheme.indigo)
                        Text(model.recordingFolderDisplayPath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 9) {
                        Button {
                            model.setRecordingFolder("")
                        } label: {
                            Label("Reset to Default", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(MMSecondaryButtonStyle())
                        .disabled(model.status.isActive)

                        Button {
                            try? FileManager.default.createDirectory(
                                at: model.recordingFolderURL,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(model.recordingFolderURL)
                        } label: {
                            Label("Open Folder", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(MMSecondaryButtonStyle())

                        Spacer()
                    }

                    Text("Leave the field empty to use ~/Movies/MotoMirror. Enable “Record session” in Mirror options before starting a mirror.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(
                    title: "Screenshots",
                    subtitle: "Always saved to Pictures",
                    icon: "camera"
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 10))
                            .foregroundStyle(MMTheme.indigo)
                        Text(model.screenshotFolderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("Each screenshot is revealed in Finder after it is saved.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            AppMark(size: 62)
            VStack(spacing: 4) {
                Text("MotoMirror")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Version 1.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("A native Mac front end for scrcpy 5.0.1 and Android platform-tools.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                StatusPill(text: "SwiftUI", tint: MMTheme.indigo, compact: true)
                StatusPill(text: "macOS 13+", tint: MMTheme.teal, compact: true)
                StatusPill(text: "No external packages", tint: MMTheme.gray, compact: true)
            }

            Divider().frame(width: 220)

            Button("Reset All Settings…") {
                showResetConfirmation = true
            }
            .buttonStyle(MMSecondaryButtonStyle(tint: MMTheme.red))
            .disabled(model.status.isActive)

            Text("Recorded video and screenshots are never deleted by a reset.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Actions

    private func chooseRecordingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.recordingFolderURL
        panel.prompt = "Choose Folder"
        panel.message = "Choose where MotoMirror saves recorded MP4 files."
        if panel.runModal() == .OK, let url = panel.url {
            model.setRecordingFolder(url.path)
        }
    }

    private func resetEverything() {
        model.resetAllSettings()
        adbPath = ""
        scrcpyPath = ""
    }

    private func flashSaved() {
        savedPulse = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            savedPulse = false
        }
    }
}

// MARK: - Settings components

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle, icon: icon)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mmCard(padding: 16)
    }
}

private struct SettingsField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

private struct SettingsToolRow: View {
    let name: String
    let path: String?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: path == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(path == nil ? MMTheme.orange : MMTheme.green)
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 48, alignment: .leading)
            Text(path ?? "Not found")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            StatusPill(
                text: path == nil ? "Missing" : "Found",
                tint: path == nil ? MMTheme.orange : MMTheme.green,
                compact: true
            )
        }
    }
}
