import Foundation

/// Collapses the two serials `adb` can report for one wirelessly-debugged
/// phone. Android advertises an mDNS serial such as
/// `adb-R5CX1234567-AbCdEf._adb-tls-connect._tcp`, while the same phone can
/// also appear as an `IP:port` alias. Reachability decides which alias wins;
/// when both are equally reachable, the mDNS serial wins because it survives
/// wireless debugging port changes.
public enum DeviceListNormalizer {
    public static func normalize(_ devices: [AndroidDevice]) -> [AndroidDevice] {
        let mdnsIndices = devices.indices.filter { isMDNSSerial(devices[$0].serial) }
        guard !mdnsIndices.isEmpty else { return devices }

        var droppedIndices = Set<Int>()
        for (ipIndex, ipDevice) in devices.enumerated() where isIPAlias(ipDevice) {
            let candidates = mdnsIndices.filter { index in
                !droppedIndices.contains(index) && samePhone(devices[index], ipDevice)
            }
            guard let mdnsIndex = bestCandidate(candidates, in: devices) else { continue }

            if preferMDNS(devices[mdnsIndex], over: ipDevice) {
                droppedIndices.insert(ipIndex)
            } else {
                droppedIndices.insert(mdnsIndex)
            }
        }

        guard !droppedIndices.isEmpty else { return devices }
        return devices.enumerated()
            .filter { !droppedIndices.contains($0.offset) }
            .map(\.element)
    }

    /// A reachable `.device` alias always wins. Otherwise the alias in the
    /// more usable state wins, with ties going to the stable mDNS serial.
    private static func preferMDNS(_ mdns: AndroidDevice, over ip: AndroidDevice) -> Bool {
        usabilityRank(mdns.state) >= usabilityRank(ip.state)
    }

    private static func usabilityRank(_ state: AndroidDevice.State) -> Int {
        switch state {
        case .device: return 4
        case .unauthorized: return 3
        case .authorizing, .connecting: return 2
        case .offline: return 1
        case .unknown: return 0
        }
    }

    private static func bestCandidate(_ indices: [Int], in devices: [AndroidDevice]) -> Int? {
        indices.max { lhs, rhs in
            let lhsRank = usabilityRank(devices[lhs].state)
            let rhsRank = usabilityRank(devices[rhs].state)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs > rhs
        }
    }

    private static func isMDNSSerial(_ serial: String) -> Bool {
        serial.range(of: "_adb-tls-connect._tcp", options: .caseInsensitive) != nil
    }

    private static func isIPAlias(_ device: AndroidDevice) -> Bool {
        guard !isMDNSSerial(device.serial) else { return false }
        return WirelessEndpoint(serial: device.serial) != nil
    }

    /// Two aliases describe the same phone when at least one identity field
    /// (`model` or `product`) is present on both sides and equal, and no
    /// field that both sides carry conflicts.
    private static func samePhone(_ lhs: AndroidDevice, _ rhs: AndroidDevice) -> Bool {
        let lhsModel = normalized(lhs.model)
        let rhsModel = normalized(rhs.model)
        let lhsProduct = normalized(lhs.product)
        let rhsProduct = normalized(rhs.product)

        var matched = false

        if let lhsModel, let rhsModel {
            guard lhsModel == rhsModel else { return false }
            matched = true
        }
        if let lhsProduct, let rhsProduct {
            guard lhsProduct == rhsProduct else { return false }
            matched = true
        }

        return matched
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let collapsed = normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
