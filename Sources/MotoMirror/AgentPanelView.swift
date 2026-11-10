import AppKit
import MotoMirrorCore
import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mmSnapshotLayout) private var isSnapshotLayout

    @State private var search = ""
    @State private var includeSystem = false
    @State private var uiText = ""
    @State private var logLines: [String] = []
    @State private var actionMessage: String?

    private var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.installedApps }
        return model.installedApps.filter { $0.package.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            if isSnapshotLayout {
                panelContent
            } else {
                ScrollView { panelContent }
            }
        }
        .frame(width: 780, height: 620)
        .background(MMTheme.pageFill)
        .task {
            if model.installedApps.isEmpty {
                await model.loadInstalledApps(includeSystem: includeSystem)
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            mcpCard
            quickActions
            appsCard
            if !logLines.isEmpty { logCard }
            if let actionMessage {
                Text(actionMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MMTheme.brandGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: "terminal")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent control")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("Drive apps, UI, files, shell, and MCP from the selected phone")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(MMIconButtonStyle(size: 26))
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }

    private var mcpCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "MCP for agents",
                subtitle: "stdio JSON-RPC; 27 tools",
                icon: "point.3.connected.trianglepath.dotted"
            )
            HStack {
                Text("motomirrorctl mcp")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("motomirrorctl mcp", forType: .string)
                }
                .buttonStyle(MMSecondaryButtonStyle())
            }
            Text("Cable-only agents can use `motomirrorctl --usb …`; no wireless debugging or pairing is required.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .mmCard(padding: 14)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "Quick actions", subtitle: "Selected device", icon: "bolt")
            HStack(spacing: 8) {
                Button {
                    Task { await model.runAgentAction(.dumpUI) }
                } label: { Label("Dump UI", systemImage: "rectangle.3.group") }
                    .buttonStyle(MMSecondaryButtonStyle())
                Button {
                    Task { await model.runAgentAction(.wake) }
                } label: { Label("Wake", systemImage: "sun.max") }
                    .buttonStyle(MMSecondaryButtonStyle())
                Button {
                    model.takeScreenshot()
                } label: { Label("Screenshot", systemImage: "camera") }
                    .buttonStyle(MMSecondaryButtonStyle())
                Button {
                    Task { logLines = await model.loadLogcat(lines: 50) }
                } label: { Label("Logcat", systemImage: "text.alignleft") }
                    .buttonStyle(MMSecondaryButtonStyle())
            }
            HStack(spacing: 8) {
                if isSnapshotLayout {
                    Text("Text to type into the focused field")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                } else {
                    TextField("Text to type into the focused field", text: $uiText)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Type") {
                    Task { await model.runAgentAction(.typeText(uiText)) }
                }
                .buttonStyle(MMPrimaryButtonStyle())
                .disabled(uiText.isEmpty)
            }
            if let message = model.agentMessage {
                Text(message).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .mmCard(padding: 14)
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Installed apps", subtitle: "Launch or stop by package", icon: "square.grid.2x2")
                Spacer()
                if isSnapshotLayout {
                    Text("System apps")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("System", isOn: $includeSystem)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: includeSystem) { value in
                            Task { await model.loadInstalledApps(includeSystem: value) }
                        }
                }
                Button {
                    Task { await model.loadInstalledApps(includeSystem: includeSystem) }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(MMIconButtonStyle(size: 24))
                    .help("Reload apps")
            }
            if isSnapshotLayout {
                Text("Search packages")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            } else {
                TextField("Search packages", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            if model.isLoadingApps {
                ProgressView().controlSize(.small)
            } else if filteredApps.isEmpty {
                Text(model.installedApps.isEmpty ? "No apps loaded. Select a device and reload." : "No packages match.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(filteredApps.prefix(80), id: \.package) { app in
                        HStack(spacing: 8) {
                            Text(app.package)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Launch") {
                                Task { await model.runAgentAction(.launch(app.package)) }
                            }
                            .buttonStyle(MMQuietButtonStyle())
                            Button("Stop") {
                                Task { await model.runAgentAction(.stop(app.package)) }
                            }
                            .buttonStyle(MMQuietButtonStyle())
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .mmCard(padding: 14)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Logcat", subtitle: "Last 50 lines", icon: "text.alignleft")
            Text(logLines.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .foregroundStyle(Color.white.opacity(0.86))
        }
        .mmCard(padding: 14)
    }
}
