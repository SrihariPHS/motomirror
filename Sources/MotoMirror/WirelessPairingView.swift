import MotoMirrorCore
import SwiftUI

struct WirelessPairingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var pairingPort = ""
    @State private var pairingCode = ""
    @State private var connectPort = "5555"
    @State private var validationMessage: String?
    @State private var discoveryInfo: String?
    @State private var tailscaleNote: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectionFields
                    if let validationMessage {
                        inlineError(validationMessage)
                    }
                    tailscaleCard
                    instructions
                }
                .padding(22)
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 552, height: 656)
        .background(MMTheme.pageFill)
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MMTheme.brandGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: "wifi")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pair over Wi-Fi")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("Android 11 or newer · same network as this Mac")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(MMIconButtonStyle(size: 26))
            .disabled(model.isPairing)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "Phone address",
                subtitle: "Discover automatically or copy the values from the phone",
                icon: "network"
            )

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Host")
                HStack(spacing: 8) {
                    TextField("192.168.1.42", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing || model.isDiscoveringWireless)
                        .accessibilityLabel("Phone IP address")

                    Button {
                        discover()
                    } label: {
                        HStack(spacing: 5) {
                            if model.isDiscoveringWireless {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "wifi")
                            }
                            Text(model.isDiscoveringWireless ? "Discovering…" : "Discover")
                        }
                    }
                    .buttonStyle(MMSecondaryButtonStyle())
                    .disabled(model.isPairing || model.isDiscoveringWireless)
                    .help("Find the phone's wireless debugging service")
                }
                Text("The address shown under Wireless debugging.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)

                if model.isDiscoveringWireless {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Looking for the phone's wireless debugging service…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                } else if let discoveryInfo {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MMTheme.green)
                            .padding(.top, 1)
                        Text(discoveryInfo)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Pairing port")
                    TextField("37123", text: $pairingPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing || model.isDiscoveringWireless)
                        .accessibilityLabel("Pairing port")
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Pairing code")
                    TextField("123456", text: $pairingCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing || model.isDiscoveringWireless)
                        .accessibilityLabel("Six digit pairing code")
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Connect port")
                    TextField("5555", text: $connectPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing || model.isDiscoveringWireless)
                        .accessibilityLabel("Wireless connection port")
                }
            }

            Text("Discover finds the host and ports from the phone's pairing dialog. If it doesn't find the phone, type the values manually. The connect port is usually 5555.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .mmCard(padding: 16)
    }

    private var tailscaleCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MMTheme.indigo.opacity(0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: "network")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MMTheme.indigo)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tailscale")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Reach a phone on your tailnet")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    tailscaleNote = nil
                    Task { await model.discoverTailscalePeers() }
                } label: {
                    HStack(spacing: 5) {
                        if model.isDiscoveringTailscale {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(model.isDiscoveringTailscale ? "Finding…" : "Find Tailscale phones")
                    }
                }
                .buttonStyle(MMSecondaryButtonStyle())
                .disabled(model.isDiscoveringTailscale || model.isPairing)
            }

            if model.isDiscoveringTailscale {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Looking for Android peers on your tailnet…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            } else if let message = model.tailscaleMessage {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.tailscalePeers.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(model.tailscalePeers.prefix(4))) { peer in
                        Button {
                            chooseTailscalePeer(peer)
                        } label: {
                            tailscalePeerRow(peer)
                        }
                        .buttonStyle(.plain)
                        .disabled(peer.ipv4 == nil && peer.dnsName == nil)
                    }
                }
            }

            if let tailscaleNote {
                Text(tailscaleNote)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(MMTheme.indigo.opacity(0.045))
                    )
            }
        }
        .mmCard(padding: 14)
    }

    private func tailscalePeerRow(_ peer: TailscalePeer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(peer.online ? MMTheme.indigo : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.hostName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(peer.ipv4 ?? peer.dnsName ?? "No address")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusPill(
                text: peer.online ? "Online" : "Offline",
                tint: peer.online ? MMTheme.green : MMTheme.gray,
                compact: true
            )
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .contentShape(Rectangle())
    }

    private func chooseTailscalePeer(_ peer: TailscalePeer) {
        guard let address = peer.ipv4 ?? peer.dnsName else { return }
        host = address
        connectPort = "5555"
        validationMessage = nil
        discoveryInfo = nil
        tailscaleNote = "Start adb tcpip 5555 on the phone once, or use the current Wireless debugging port. Android may block inbound ADB over VPN; test the address before relying on it."
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "On the phone",
                subtitle: "Same Wi-Fi network as this Mac",
                icon: "iphone"
            )
            NumberedStep(
                number: 1,
                title: "Open Wireless debugging",
                detail: "Settings → System → Developer options → Wireless debugging, then turn it on.",
                icon: "wifi"
            )
            NumberedStep(
                number: 2,
                title: "Pair device with pairing code",
                detail: "Tap “Pair device with pairing code” and keep that dialog open. The phone shows a host, port, and six-digit code.",
                icon: "number"
            )
            NumberedStep(
                number: 3,
                title: "Click Discover",
                detail: "MotoMirror finds the phone's host, pairing port, and connect port. Manual entry still works as a fallback.",
                icon: "arrow.right"
            )
            NumberedStep(
                number: 4,
                title: "Enter the code and connect",
                detail: "Type the six-digit code, then click Pair & Connect.",
                icon: "link"
            )
        }
        .mmCard(padding: 16)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MMTheme.orange)
            Text(message)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MMTheme.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MMTheme.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isPairing {
                ProgressView()
                    .controlSize(.small)
                Text("Pairing and connecting…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Tip: keep the phone unlocked.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(MMSecondaryButtonStyle())
            .disabled(model.isPairing)

            Button {
                submit()
            } label: {
                Label("Pair & Connect", systemImage: "link")
            }
            .buttonStyle(MMPrimaryButtonStyle())
            .disabled(model.isPairing || model.isDiscoveringWireless)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func discover() {
        guard !model.isDiscoveringWireless, !model.isPairing else { return }
        validationMessage = nil
        discoveryInfo = nil

        Task {
            let result = await model.discoverWirelessEndpoint()
            if let result {
                host = result.host
                if let pairingPortValue = result.pairingPort {
                    pairingPort = String(pairingPortValue)
                } else {
                    pairingPort = ""
                }
                if let connectPortValue = result.connectPort {
                    connectPort = String(connectPortValue)
                }

                if result.pairingPort == nil {
                    validationMessage = model.wirelessDiscoveryMessage
                } else {
                    validationMessage = nil
                    discoveryInfo = model.wirelessDiscoveryMessage
                }
            } else {
                validationMessage = model.wirelessDiscoveryMessage
                    ?? "No wireless debugging service was found."
            }
        }
    }

    private func submit() {
        guard !model.isDiscoveringWireless else { return }
        validationMessage = nil
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            validationMessage = "Enter the phone's IP address, for example 192.168.1.42."
            return
        }
        guard !trimmedHost.contains("://"), !trimmedHost.contains("/"), !trimmedHost.contains(":") else {
            validationMessage = "Enter only the IP address in Host. Use the fields below for ports."
            return
        }
        guard let parsedPairingPort = Int(pairingPort.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(parsedPairingPort) else {
            validationMessage = "Enter the pairing port shown on the phone (1–65535)."
            return
        }
        let trimmedCode = pairingCode.trimmingCharacters(in: .whitespaces)
        guard trimmedCode.count == 6, trimmedCode.allSatisfy({ $0.isNumber }) else {
            validationMessage = "Enter the six-digit pairing code shown on the phone."
            return
        }
        guard let parsedConnectPort = Int(connectPort.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(parsedConnectPort) else {
            validationMessage = "Enter a valid connect port, usually 5555."
            return
        }

        Task {
            do {
                try await model.pairAndConnect(
                    host: trimmedHost,
                    pairingPort: parsedPairingPort,
                    code: trimmedCode,
                    connectPort: parsedConnectPort
                )
                dismiss()
            } catch {
                validationMessage = AppModel.friendlyMessage(for: error)
            }
        }
    }
}

private struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
