import MotoMirrorCore
import SwiftUI

struct OptionsView: View {
    @ObservedObject var model: AppModel
    var showsHeader = true

    private var isLocked: Bool { model.status.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if showsHeader {
                SectionHeader(
                    title: "Mirror options",
                    subtitle: "Tune quality and window behavior",
                    icon: "slider.horizontal.3",
                    trailing: AnyView(
                        isLocked
                            ? AnyView(
                                Label("Locked while mirroring", systemImage: "lock.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            )
                            : AnyView(EmptyView())
                    )
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                PresetControl(model: model)

                Divider().opacity(0.55)

                HStack(alignment: .top, spacing: 14) {
                    SegmentedOption(
                        title: "Max size",
                        choices: [("Native", 0), ("720", 720), ("1080", 1080), ("1440", 1440), ("1920", 1920)],
                        selection: $model.options.maxSize
                    )
                    SegmentedOption(
                        title: "Bit rate (Mbps)",
                        choices: [("4", 4), ("8", 8), ("12", 12), ("20", 20)],
                        selection: $model.options.videoBitRateMbps
                    )
                    SegmentedOption(
                        title: "Frame rate (fps)",
                        choices: [("30", 30), ("60", 60), ("90", 90)],
                        selection: $model.options.maxFPS
                    )
                }

                Divider().opacity(0.55)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12, alignment: .leading)],
                    alignment: .leading,
                    spacing: 11
                ) {
                    OptionToggle(
                        title: "Audio",
                        detail: "Play phone sound here",
                        icon: "speaker.wave.2",
                        isOn: $model.options.audioEnabled
                    )
                    OptionToggle(
                        title: "Stay awake",
                        detail: "Keep the screen on",
                        icon: "sun.max",
                        isOn: $model.options.stayAwake
                    )
                    OptionToggle(
                        title: "Turn screen off",
                        detail: "Mirror with display dark",
                        icon: "moon",
                        isOn: $model.options.turnScreenOff
                    )
                    OptionToggle(
                        title: "Show touches",
                        detail: "Draw taps on screen",
                        icon: "hand.tap",
                        isOn: $model.options.showTouches
                    )
                    OptionToggle(
                        title: "Always on top",
                        detail: "Float over other windows",
                        icon: "pin",
                        isOn: $model.options.alwaysOnTop
                    )
                    OptionToggle(
                        title: "Fullscreen",
                        detail: "Hide window chrome",
                        icon: "arrow.up.left.and.arrow.down.right",
                        isOn: $model.options.fullscreen
                    )
                    OptionToggle(
                        title: "Record session",
                        detail: "Save a timestamped MP4",
                        icon: "record.circle",
                        isOn: $model.options.recordEnabled
                    )
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.72 : 1)
            }
            .disabled(isLocked)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                Text(
                    model.options.recordEnabled
                        ? "MP4 saves to \(model.recordingFolderDisplayPath)"
                        : "Recordings are saved to \(model.recordingFolderDisplayPath)"
                )
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)

            if isLocked {
                Label("Stop mirroring to change these settings.", systemImage: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PresetControl: View {
    @ObservedObject var model: AppModel
    @Environment(\.mmSnapshotLayout) private var isSnapshot

    private let presets: [MirrorPreset] = [.quality, .balanced, .batterySaver]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mirror preset")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            if isSnapshot {
                HStack(spacing: 2) {
                    ForEach(presets, id: \.self) { preset in
                        Text(label(for: preset))
                            .font(.system(size: 10.5, weight: model.preset == preset ? .semibold : .regular))
                            .foregroundStyle(model.preset == preset ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 21)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(
                                        model.preset == preset
                                            ? MMTheme.indigo
                                            : Color.primary.opacity(0.04)
                                    )
                            )
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            } else {
                Picker("Mirror preset", selection: presetSelection) {
                    ForEach(presets, id: \.self) { preset in
                        Text(label(for: preset)).tag(Optional(preset))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.preset.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(MMTheme.indigo)
                Text(model.preset.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(model.preset.batteryNote)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MMTheme.indigo.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MMTheme.indigo.opacity(0.10), lineWidth: 1)
        )
    }

    private var presetSelection: Binding<MirrorPreset?> {
        Binding(
            get: { model.preset == .custom ? nil : model.preset },
            set: { value in
                if let value {
                    model.preset = value
                }
            }
        )
    }

    private func label(for preset: MirrorPreset) -> String {
        switch preset {
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .batterySaver: return "Battery Saver"
        case .custom: return "Custom"
        }
    }
}

private struct ChoiceField<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SegmentedOption: View {
    let title: String
    let choices: [(String, Int)]
    @Binding var selection: Int
    @Environment(\.mmSnapshotLayout) private var isSnapshot

    var body: some View {
        ChoiceField(title: title) {
            if isSnapshot {
                HStack(spacing: 2) {
                    ForEach(choices.indices, id: \.self) { index in
                        let choice = choices[index]
                        Text(choice.0)
                            .font(.system(size: 10.5, weight: choice.1 == selection ? .semibold : .regular))
                            .foregroundStyle(choice.1 == selection ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 21)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(
                                        choice.1 == selection
                                            ? MMTheme.indigo
                                            : Color.primary.opacity(0.04)
                                    )
                            )
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            } else {
                Picker(title, selection: $selection) {
                    ForEach(choices.indices, id: \.self) { index in
                        Text(choices[index].0).tag(choices[index].1)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

private struct OptionToggle: View {
    let title: String
    let detail: String
    let icon: String
    @Binding var isOn: Bool
    @Environment(\.mmSnapshotLayout) private var isSnapshot

    var body: some View {
        if isSnapshot {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? MMTheme.indigo : .secondary)
                    .frame(width: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                HStack(spacing: 3) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(
                    Capsule().fill(
                        isOn ? MMTheme.indigo : Color.primary.opacity(0.06)
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(title): \(detail)")
        } else {
            Toggle(isOn: $isOn) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isOn ? MMTheme.indigo : .secondary)
                        .frame(width: 15)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("\(title): \(detail)")
        }
    }
}
