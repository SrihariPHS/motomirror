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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectionFields
                    instructions
                    if let validationMessage {
                        inlineError(validationMessage)
                    }
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
                subtitle: "Copy these values from the phone's pairing dialog",
                icon: "network"
            )

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Host")
                TextField("192.168.1.42", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .disabled(model.isPairing)
                    .accessibilityLabel("Phone IP address")
                Text("The IP address shown under Wireless debugging.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Pairing port")
                    TextField("37123", text: $pairingPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing)
                        .accessibilityLabel("Pairing port")
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Pairing code")
                    TextField("123456", text: $pairingCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing)
                        .accessibilityLabel("Six digit pairing code")
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Connect port")
                    TextField("5555", text: $connectPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(model.isPairing)
                        .accessibilityLabel("Wireless connection port")
                }
            }

            Text("The pairing port and code appear only in the “Pair device with pairing code” dialog. The connect port is usually 5555.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .mmCard(padding: 16)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "On the phone",
                subtitle: "Enable Wireless debugging first",
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
                detail: "Tap “Pair device with pairing code”. The phone shows an IP address, a port, and a six-digit code.",
                icon: "number"
            )
            NumberedStep(
                number: 3,
                title: "Enter the values here",
                detail: "Type the address, pairing port, and code above. MotoMirror pairs, then connects on the normal port.",
                icon: "arrow.right"
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
            .disabled(model.isPairing)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func submit() {
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
