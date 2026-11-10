import MotoMirrorCore
import SwiftUI

// MARK: - Root

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 268, ideal: 292, max: 340)
        } detail: {
            DetailContainer(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(MMTheme.indigo)
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $model.isShowingWirelessSheet) {
            WirelessPairingView(model: model)
        }
        .sheet(isPresented: $model.isShowingSetup) {
            SetupView(model: model, presentedAsSheet: true)
                .frame(minWidth: 640, minHeight: 640)
        }
        .sheet(isPresented: $model.isShowingAgentPanel) {
            AgentPanelView(model: model)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.mmSnapshotLayout) private var isSnapshotLayout

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            deviceHeader
            deviceList
            Divider().opacity(0.45)
            footer
        }
        .background(sidebarBackground)
    }

    private var header: some View {
        HStack(spacing: 11) {
            AppMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("MotoMirror")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Android on your Mac")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                model.refreshNow()
            } label: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(MMIconButtonStyle(size: 27))
            .disabled(model.isRefreshing || !model.toolsReady)
            .help("Refresh devices (⌘R)")
            .accessibilityLabel("Refresh devices")
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 13)
    }

    private var deviceHeader: some View {
        HStack(spacing: 8) {
            Text("DEVICES")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            if !model.devices.isEmpty {
                Text("\(model.devices.count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            Spacer()
            Button {
                model.isShowingWirelessSheet = true
            } label: {
                Label("Wireless…", systemImage: "wifi")
            }
            .buttonStyle(MMQuietButtonStyle())
            .help("Pair a phone over Wi-Fi")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private var deviceList: some View {
        if model.devices.isEmpty {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(MMTheme.indigo.opacity(0.09))
                        .frame(width: 46, height: 46)
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(MMTheme.indigo.opacity(0.75))
                }
                Text("No devices yet")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Connect over USB or pair over Wi-Fi.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
        } else if isSnapshotLayout {
            VStack(spacing: 3) {
                ForEach(model.devices) { device in
                    DeviceRow(device: device)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    model.selectedSerial == device.serial
                                        ? MMTheme.indigo.opacity(0.11)
                                        : Color.clear
                                )
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(
                selection: Binding(
                    get: { model.selectedSerial },
                    set: { model.select($0) }
                )
            ) {
                ForEach(model.devices) { device in
                    DeviceRow(device: device)
                        .tag(device.serial)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Button {
                model.isShowingSetup = true
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(toolTint.opacity(0.13))
                            .frame(width: 24, height: 24)
                        Image(systemName: model.toolsReady ? "checkmark" : "wrench.and.screwdriver")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(toolTint)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.toolsReady ? "Tools ready" : "Tools missing")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(model.toolVersionSummary ?? (model.toolsReady ? "adb + scrcpy found" : "Tap to install adb and scrcpy"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(toolTint.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(toolTint.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Setup and troubleshooting")

            HStack(spacing: 6) {
                Button {
                    model.isShowingAgentPanel = true
                } label: {
                    Label("Agent", systemImage: "terminal")
                }
                .buttonStyle(MMQuietButtonStyle())
                .help("Apps, UI automation, files, and MCP")

                if !model.usbOnly {
                    Button {
                        model.isShowingWirelessSheet = true
                    } label: {
                        Label("Wireless", systemImage: "wifi")
                    }
                    .buttonStyle(MMQuietButtonStyle())
                }

                Spacer()

                Button {
                    model.isShowingSetup = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .buttonStyle(MMQuietButtonStyle())
            }
            if model.usbOnly {
                Text("USB only · no wireless debugging")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(MMTheme.teal)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var toolTint: Color {
        model.toolsReady ? MMTheme.teal : MMTheme.orange
    }

    private var sidebarBackground: some View {
        ZStack {
            MMTheme.sidebarFill.opacity(0.72)
            LinearGradient(
                colors: [MMTheme.indigo.opacity(0.045), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: 10) {
            StateDot(color: DevicePalette.color(for: device.state), size: 7)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(device.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: device.mmTransportIcon)
                        .font(.system(size: 8.5, weight: .medium))
                    Text(device.mmTransportLabel)
                    Text("·")
                    Text(device.serial)
                        .truncationMode(.middle)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 2)
            if device.state != .device {
                StatusPill(
                    text: DevicePalette.shortLabel(for: device.state),
                    tint: DevicePalette.color(for: device.state),
                    compact: true
                )
            } else {
                Image(systemName: device.mmTransportIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.displayName), \(device.mmStateLabel), \(device.mmTransportLabel)")
    }
}

// MARK: - Detail routing

struct DetailContainer: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                if let error = model.errorMessage {
                    ErrorBanner(message: error) {
                        model.dismissError()
                    }
                    .padding(.horizontal, MMTheme.pagePadding)
                    .padding(.top, 14)
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.toolsReady {
            SetupView(model: model, presentedAsSheet: false)
        } else if let device = model.selectedDevice {
            if device.state == .unauthorized {
                UnauthorizedView(model: model, device: device)
            } else if !device.isUsable {
                OfflineDeviceView(model: model, device: device)
            } else {
                ConnectedDeviceView(model: model, device: device)
            }
        } else if model.isWaitingForMirrorDevice {
            WaitingForMirrorDeviceView(model: model)
        } else {
            EmptyDevicesView(model: model)
        }
    }
}

// MARK: - Empty state

struct EmptyDevicesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        DetailScroll {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(MMTheme.brandGradient)
                            .frame(width: 54, height: 54)
                            .shadow(color: MMTheme.indigo.opacity(0.28), radius: 10, y: 4)
                        Image(systemName: "iphone")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    Text("Connect your phone")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("MotoMirror finds your Android phone, shows its live status, and opens a low-latency mirror with scrcpy.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 620, alignment: .leading)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 17) {
                    SectionHeader(
                        title: "Enable USB debugging",
                        subtitle: "About a minute on the phone",
                        icon: "number"
                    )
                    NumberedStep(
                        number: 1,
                        title: "Open Developer options",
                        detail: "On the phone, open Settings → About phone and tap Build number seven times. Enter the screen lock if asked.",
                        icon: "gearshape"
                    )
                    NumberedStep(
                        number: 2,
                        title: "Turn on USB debugging",
                        detail: "Open Settings → System → Developer options and switch on USB debugging.",
                        icon: "ladybug"
                    )
                    NumberedStep(
                        number: 3,
                        title: "Plug in and allow",
                        detail: "Connect the phone with a USB data cable. On the phone, tap Allow on the “Allow USB debugging?” prompt.",
                        icon: "cable.connector"
                    )
                }
                .mmCard(padding: 20)

                HStack(spacing: 10) {
                    Button {
                        model.refreshNow()
                    } label: {
                        Label("Refresh Devices", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MMPrimaryButtonStyle())
                    .disabled(model.isRefreshing)

                    Button {
                        model.isShowingWirelessSheet = true
                    } label: {
                        Label("Wireless Pairing…", systemImage: "wifi")
                    }
                    .buttonStyle(MMSecondaryButtonStyle())

                    Spacer()

                    HStack(spacing: 5) {
                        if model.isRefreshing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Circle()
                                .fill(MMTheme.teal)
                                .frame(width: 5, height: 5)
                        }
                        Text(model.isRefreshing ? "Looking for devices…" : "Checking every 2 seconds")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Android 11 or newer can also connect wirelessly. Enable Wireless debugging in Developer options, then use the Wireless button.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMTheme.pagePadding)
        }
    }
}

// MARK: - Unauthorized state

struct UnauthorizedView: View {
    @ObservedObject var model: AppModel
    let device: AndroidDevice

    var body: some View {
        DetailScroll {
            VStack(alignment: .leading, spacing: 22) {
                AttentionHeader(
                    icon: "lock.shield.fill",
                    tint: MMTheme.orange,
                    title: "Authorize this phone",
                    detail: "\(device.displayName) is connected over \(device.mmTransportLabel), but this Mac has not been allowed to control it yet."
                )

                VStack(alignment: .leading, spacing: 17) {
                    SectionHeader(
                        title: "Accept the USB debugging prompt",
                        subtitle: "Keep the phone unlocked while you do this",
                        icon: "checkmark.shield"
                    )
                    NumberedStep(
                        number: 1,
                        title: "Unlock the phone",
                        detail: "Keep the phone unlocked so the authorization dialog can appear.",
                        icon: "lock.open"
                    )
                    NumberedStep(
                        number: 2,
                        title: "Tap Allow",
                        detail: "On the phone, look for “Allow USB debugging?”. Check “Always allow from this computer”, then tap Allow.",
                        icon: "hand.raised"
                    )
                    NumberedStep(
                        number: 3,
                        title: "No prompt? Reset the connection",
                        detail: "Unplug and reconnect the cable. If it still does not appear, open Developer options → Revoke USB debugging authorizations, then reconnect.",
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
                .mmCard(padding: 20)

                HStack(spacing: 10) {
                    Button {
                        model.refreshNow()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MMPrimaryButtonStyle())
                    .disabled(model.isRefreshing)

                    Button {
                        model.isShowingSetup = true
                    } label: {
                        Label("Setup & Help", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(MMSecondaryButtonStyle())

                    Spacer()
                }

                deviceIdentityCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMTheme.pagePadding)
        }
    }

    private var deviceIdentityCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(MMTheme.orange)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MMTheme.orange.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(device.mmTransportLabel) · \(device.serial)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            StatusPill(text: "Needs authorization", tint: MMTheme.orange, icon: "exclamationmark")
        }
        .mmCard(padding: 14)
    }
}

// MARK: - Offline state

struct OfflineDeviceView: View {
    @ObservedObject var model: AppModel
    let device: AndroidDevice

    var body: some View {
        DetailScroll {
            VStack(alignment: .leading, spacing: 22) {
                AttentionHeader(
                    icon: "wifi.exclamationmark",
                    tint: MMTheme.red,
                    title: "\(device.displayName) is offline",
                    detail: "\(device.mmStateLabel) over \(device.mmTransportLabel). Reconnect the cable or wireless session, then refresh."
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Try this", icon: "lightbulb")
                    BulletRow(text: "Use a USB data cable, not a charge-only cable.")
                    BulletRow(text: "Unlock the phone and keep it awake while connecting.")
                    BulletRow(text: "For Wi-Fi, confirm the phone and Mac are on the same network.")
                    BulletRow(text: "For Wi-Fi, re-pair from the Wireless… button if the port changed.")
                }
                .mmCard(padding: 18)

                HStack(spacing: 10) {
                    Button {
                        model.refreshNow()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MMPrimaryButtonStyle())

                    Button {
                        model.isShowingWirelessSheet = true
                    } label: {
                        Label("Wireless Pairing…", systemImage: "wifi")
                    }
                    .buttonStyle(MMSecondaryButtonStyle())

                    Spacer()

                    StatusPill(text: device.mmStateLabel, tint: MMTheme.red, compact: true)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMTheme.pagePadding)
        }
    }
}

// MARK: - Connected

// MARK: - Waiting for reconnect

struct WaitingForMirrorDeviceView: View {
    @ObservedObject var model: AppModel

    private var deviceName: String {
        model.mirroringDeviceName ?? "your phone"
    }

    var body: some View {
        DetailScroll {
            VStack(alignment: .leading, spacing: 22) {
                AttentionHeader(
                    icon: "arrow.triangle.2.circlepath",
                    tint: MMTheme.orange,
                    title: "Reconnecting to \(deviceName)",
                    detail: "The mirror paused when the connection dropped. MotoMirror keeps checking every 2 seconds and restores the session when the phone is back."
                )

                HStack(spacing: 10) {
                    if model.isReconnecting {
                        StatusPill(
                            text: "Attempt \(model.reconnectAttempt) of \(model.reconnectAttemptLimit)",
                            tint: MMTheme.orange,
                            icon: "arrow.triangle.2.circlepath"
                        )
                    } else {
                        StatusPill(
                            text: "Waiting for phone",
                            tint: MMTheme.orange,
                            icon: "hourglass"
                        )
                    }

                    Spacer()

                    Button {
                        model.refreshNow()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MMSecondaryButtonStyle())
                    .disabled(model.isRefreshing)

                    Button {
                        model.stopMirroring()
                    } label: {
                        Label("Stop Reconnecting", systemImage: "stop.fill")
                    }
                    .buttonStyle(MMSecondaryButtonStyle(tint: MMTheme.red))
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Bring the phone back", icon: "lightbulb")
                    BulletRow(text: "Reconnect the USB data cable, or confirm the phone is on the same Wi-Fi network.")
                    BulletRow(text: "Unlock the phone and keep it awake while MotoMirror reconnects.")
                    BulletRow(text: "If the phone does not return, stop reconnecting and pair again from the Wireless… button.")
                }
                .mmCard(padding: 18)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMTheme.pagePadding)
        }
    }
}

struct ConnectedDeviceView: View {
    @ObservedObject var model: AppModel
    let device: AndroidDevice
    @Environment(\.mmSnapshotLayout) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            DetailScroll {
                VStack(alignment: .leading, spacing: 15) {
                    DeviceHeader(model: model, device: device)

                    HStack(alignment: .top, spacing: 14) {
                        BatteryCard(battery: model.details?.battery)
                        StorageCard(storage: model.details?.storage)
                    }
                    .frame(maxWidth: .infinity)

                    DeviceInfoCard(details: model.details)

                    OptionsView(model: model)
                        .mmCard(padding: 16)

                    if isSnapshot {
                        SnapshotSessionLogCard(logs: model.logs)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(
                                title: "Session log",
                                subtitle: "MotoMirror actions and scrcpy output",
                                icon: "terminal",
                                trailing: AnyView(
                                    Text("\(model.logs.count) lines")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                                )
                            )
                            LogConsoleView(logs: model.logs, onClear: { model.clearLogs() })
                        }
                        .mmCard(padding: 14)
                    }
                }
                .padding(MMTheme.pagePadding)
                .padding(.bottom, 4)
            }

            Divider().opacity(0.5)

            MirrorActionCard(model: model)
                .padding(.horizontal, MMTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(MMTheme.pageFill.opacity(0.94))
        }
    }
}

// MARK: - Connected header

private struct DeviceHeader: View {
    @ObservedObject var model: AppModel
    let device: AndroidDevice

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MMTheme.brandGradient)
                    .frame(width: 52, height: 52)
                    .shadow(color: MMTheme.indigo.opacity(0.24), radius: 8, y: 3)
                Image(systemName: "iphone")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(device.displayName)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    StatusPill(
                        text: statusText,
                        tint: statusTint,
                        icon: statusIcon
                    )
                }
                HStack(spacing: 9) {
                    Label(device.serial, systemImage: "number")
                        .textSelection(.enabled)
                    Label(device.mmTransportLabel, systemImage: device.mmTransportIcon)
                    if let manufacturer = model.details?.manufacturer, !manufacturer.isEmpty {
                        Text(manufacturer)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let started = model.status.startedAt, model.status.isActive {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SESSION")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    Text(MMFormat.sessionTime(started))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let pid = model.status.pid {
                        Text("PID \(pid)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var statusText: String {
        if model.isReconnecting { return "Reconnecting" }
        if model.isWaitingForDevice { return "Waiting for phone" }
        if model.status.state == .failed { return "Mirror failed" }
        if model.status.isActive { return model.mirrorStatusText }
        return "Connected"
    }

    private var statusTint: Color {
        if model.isReconnecting || model.isWaitingForDevice { return MMTheme.orange }
        switch model.status.state {
        case .failed: return MMTheme.red
        case .starting, .stopping: return MMTheme.blue
        case .running: return MMTheme.teal
        default: return MMTheme.green
        }
    }

    private var statusIcon: String? {
        if model.isReconnecting { return "arrow.triangle.2.circlepath" }
        if model.isWaitingForDevice { return "hourglass" }
        switch model.status.state {
        case .failed: return "exclamationmark"
        case .running: return "play.fill"
        case .starting, .stopping: return "hourglass"
        default: return "checkmark"
        }
    }
}

// MARK: - Cards

private struct BatteryCard: View {
    let battery: BatteryInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(levelText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            MeterBar(fraction: Double(battery?.level ?? 0) / 100.0, tint: tint)
            HStack(spacing: 8) {
                if let status = battery?.status, !status.isEmpty {
                    Label(status, systemImage: battery?.isCharging == true ? "bolt.fill" : "minus")
                } else {
                    Text("Status unavailable")
                }
                Spacer()
                if let temperature = battery?.temperatureCelsius {
                    Text(String(format: "%.1f °C", temperature))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mmCard(padding: 14)
    }

    private var levelText: String {
        guard let level = battery?.level else { return "—" }
        return "\(level)%"
    }

    private var tint: Color {
        MMTheme.batteryColor(level: battery?.level)
    }

    private var batteryIcon: String {
        guard let level = battery?.level else { return "battery.0" }
        switch level {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }
}

private struct StorageCard: View {
    let storage: StorageInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MMTheme.indigo)
                Text("Storage")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(usedText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(MMTheme.indigo)
                    .contentTransition(.numericText())
            }
            MeterBar(fraction: storage?.usedFraction ?? 0, tint: MMTheme.indigo)
            HStack(spacing: 8) {
                if let storage {
                    Text("\(MMFormat.bytes(storage.availableBytes)) free of \(MMFormat.bytes(storage.totalBytes))")
                } else {
                    Text("Storage unavailable")
                }
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mmCard(padding: 14)
    }

    private var usedText: String {
        guard let storage else { return "—" }
        return "\(Int((storage.usedFraction * 100).rounded()))%"
    }
}

private struct DeviceInfoCard: View {
    let details: DeviceDetails?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Device info",
                subtitle: subtitle,
                icon: "info.circle"
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 145), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                MetricTile(
                    icon: "gearshape",
                    title: "Android",
                    value: details?.androidVersion.map { "Android \($0)" } ?? "—",
                    caption: "Version"
                )
                MetricTile(
                    icon: "hammer",
                    title: "SDK",
                    value: details?.sdk ?? "—",
                    caption: "API level"
                )
                MetricTile(
                    icon: "display",
                    title: "Screen",
                    value: screenText,
                    caption: screenCaption
                )
                MetricTile(
                    icon: "cpu",
                    title: "Chip",
                    value: details?.abi ?? "—",
                    caption: "Architecture"
                )
            }
        }
        .mmCard(padding: 14)
    }

    private var subtitle: String {
        guard let details else { return "Waiting for phone details" }
        let parts = [details.manufacturer, details.model].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? details.serial : parts.joined(separator: " · ")
    }

    private var screenText: String {
        guard let screen = details?.screen else { return "—" }
        return "\(screen.width) × \(screen.height)"
    }

    private var screenCaption: String {
        guard let density = details?.screen?.density else { return "Resolution" }
        return "\(density) dpi"
    }
}

private struct SnapshotSessionLogCard: View {
    let logs: [AppLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MMTheme.indigo)
                Text("Session log")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(logs.count) lines")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if let entry = logs.last {
                HStack(spacing: 7) {
                    Text(MMFormat.clock(entry.date))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(entry.source.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(sourceColor(entry.source))
                    Text(entry.message)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(red: 0.064, green: 0.071, blue: 0.11))
                )
            }
        }
        .mmCard(padding: 12)
    }

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "scrcpy": return Color(red: 0.40, green: 0.85, blue: 0.80)
        case "adb": return Color(red: 0.55, green: 0.70, blue: 1.0)
        default: return Color(red: 0.72, green: 0.72, blue: 0.95)
        }
    }
}

private struct MirrorActionCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subheadline)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.isReconnecting {
                    StatusPill(
                        text: "Attempt \(model.reconnectAttempt) of \(model.reconnectAttemptLimit)",
                        tint: MMTheme.orange,
                        icon: "arrow.triangle.2.circlepath"
                    )
                } else if model.isWaitingForDevice {
                    StatusPill(text: "Waiting for phone", tint: MMTheme.orange, icon: "hourglass")
                } else {
                    StatusPill(
                        text: model.mirrorStatusText,
                        tint: statusTint,
                        icon: statusIcon
                    )
                }

                Button {
                    model.toggleMirroring()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.status.isActive || model.isRecovering ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(model.mirrorButtonTitle)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 170)
                }
                .buttonStyle(
                    MMPrimaryButtonStyle(
                        tint: model.status.isActive || model.isRecovering ? MMTheme.red : MMTheme.indigo,
                        large: true
                    )
                )
                .disabled(stopButtonDisabled)
                .keyboardShortcut(.return, modifiers: [.command])
                .help(model.status.isActive || model.isRecovering ? "Stop mirroring (⌘⇧M)" : "Start mirroring (⌘⇧M)")
            }

            HStack(spacing: 8) {
                Button {
                    model.takeScreenshot()
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }
                .buttonStyle(MMSecondaryButtonStyle())
                .disabled(!model.canUseSelectedDevice)
                .help("Save a PNG to Pictures/MotoMirror (⌘⇧S)")

                Button {
                    model.options.recordEnabled.toggle()
                } label: {
                    Label(
                        model.options.recordEnabled ? "Recording On" : "Record Session",
                        systemImage: model.options.recordEnabled ? "record.circle.fill" : "record.circle"
                    )
                    .foregroundStyle(model.options.recordEnabled ? MMTheme.red : .primary)
                }
                .buttonStyle(MMSecondaryButtonStyle(tint: model.options.recordEnabled ? MMTheme.red : .primary))
                .disabled(model.status.isActive || !model.canUseSelectedDevice)
                .help("Record an MP4 while mirroring; choose a folder in Settings")

                if model.recordingURL != nil {
                    Button {
                        model.revealRecording()
                    } label: {
                        Label("Reveal Recording", systemImage: "folder")
                    }
                    .buttonStyle(MMSecondaryButtonStyle())
                }

                Spacer(minLength: 4)

                if let lastRefresh = model.lastRefresh {
                    Text("Refreshed \(MMFormat.clock(lastRefresh))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .mmCard(padding: 12)
    }

    private var headline: String {
        if model.isReconnecting { return "Restoring the mirror session" }
        if model.isWaitingForDevice { return "Waiting for the phone to return" }
        switch model.status.state {
        case .running: return "Mirror session active"
        case .starting: return "Opening the mirror window"
        case .stopping: return "Closing the mirror window"
        case .failed: return "The mirror session stopped"
        case .stopped: return "Mirror session ended"
        default: return "Ready to mirror"
        }
    }

    private var subheadline: String {
        if model.isReconnecting {
            return "The phone is still connected. MotoMirror tries up to \(model.reconnectAttemptLimit) times."
        }
        if model.isWaitingForDevice {
            return "Reconnect over USB or Wi-Fi; mirroring resumes automatically."
        }
        switch model.status.state {
        case .running:
            return "\(model.options.videoBitRateMbps) Mbps · \(model.options.maxFPS) fps · \(sizeLabel)"
        case .failed:
            return model.status.message ?? "Check the session log, then try again."
        case .stopped:
            return "Start again whenever you are ready."
        default:
            return "\(sizeLabel) · \(model.options.videoBitRateMbps) Mbps · \(model.options.maxFPS) fps · \(model.options.audioEnabled ? "audio on" : "audio off")"
        }
    }

    private var sizeLabel: String {
        model.options.maxSize == 0 ? "native size" : "\(model.options.maxSize)p"
    }

    private var stopButtonDisabled: Bool {
        if model.status.state == .stopping { return true }
        if model.status.isActive || model.isRecovering { return false }
        return !model.canStartMirroring
    }

    private var statusTint: Color {
        switch model.status.state {
        case .failed: return MMTheme.red
        case .starting, .stopping: return MMTheme.blue
        case .running: return MMTheme.teal
        case .stopped: return MMTheme.gray
        default: return MMTheme.green
        }
    }

    private var statusIcon: String? {
        switch model.status.state {
        case .failed: return "exclamationmark"
        case .running: return "play.fill"
        case .starting, .stopping: return "hourglass"
        case .stopped: return "pause.fill"
        default: return "checkmark"
        }
    }
}

// MARK: - Shared detail pieces

struct AttentionHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(MMTheme.indigo.opacity(0.55))
                .frame(width: 4, height: 4)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MMTheme.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(MMIconButtonStyle(size: 22))
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MMTheme.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MMTheme.orange.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Palette

enum DevicePalette {
    static func color(for state: AndroidDevice.State) -> Color {
        switch state {
        case .device: return MMTheme.green
        case .unauthorized: return MMTheme.orange
        case .offline: return MMTheme.red
        case .authorizing, .connecting: return MMTheme.blue
        case .unknown: return MMTheme.gray
        }
    }

    static func shortLabel(for state: AndroidDevice.State) -> String {
        switch state {
        case .device: return "Ready"
        case .unauthorized: return "Authorize"
        case .offline: return "Offline"
        case .authorizing: return "Authorizing"
        case .connecting: return "Connecting"
        case .unknown: return "Unknown"
        }
    }
}
