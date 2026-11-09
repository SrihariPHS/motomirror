import AppKit
import SwiftUI

struct LogConsoleView: View {
    let logs: [AppLogEntry]
    var onClear: (() -> Void)?

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
                .overlay(Color.white.opacity(0.08))
            console
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.075, green: 0.085, blue: 0.13),
                            Color(red: 0.055, green: 0.06, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MMTheme.green)
                .frame(width: 6, height: 6)
            Text("CONSOLE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            Text("\(logs.count)")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.32))
            Spacer()
            Button {
                copyLogs()
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .disabled(logs.isEmpty)
            .accessibilityLabel("Copy session log")

            Button {
                onClear?()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .disabled(logs.isEmpty)
            .accessibilityLabel("Clear session log")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if logs.isEmpty {
                        Text("Activity will appear here as MotoMirror works.")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.32))
                            .padding(.vertical, 6)
                    } else {
                        ForEach(logs) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: logs.count) { _ in
                scrollToBottom(proxy, animated: true)
            }
        }
        .frame(minHeight: 118, idealHeight: 165, maxHeight: 205)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = logs.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.14)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func copyLogs() {
        let text = logs.map { entry in
            "\(MMFormat.clock(entry.date)) [\(entry.source)] \(entry.message)"
        }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }
}

private struct LogRow: View {
    let entry: AppLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(MMFormat.clock(entry.date))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.33))
                .frame(width: 50, alignment: .leading)
            Text(entry.source.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(sourceColor)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 1)
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(levelColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceColor: Color {
        switch entry.source {
        case "scrcpy": return Color(red: 0.40, green: 0.85, blue: 0.80)
        case "adb": return Color(red: 0.55, green: 0.70, blue: 1.0)
        default: return Color(red: 0.72, green: 0.72, blue: 0.95)
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: return .white.opacity(0.78)
        case .success: return Color(red: 0.52, green: 0.90, blue: 0.68)
        case .warning: return Color(red: 0.98, green: 0.76, blue: 0.38)
        case .error: return Color(red: 1.0, green: 0.52, blue: 0.52)
        }
    }
}
