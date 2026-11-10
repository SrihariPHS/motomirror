import AppKit
import Combine
import Foundation
import MotoMirrorCore

// MARK: - Preferences

enum MMDefaults {
    static let options = "MotoMirror.options"
    static let adbPath = "MotoMirror.adbPath"
    static let scrcpyPath = "MotoMirror.scrcpyPath"
    static let recordingFolder = "MotoMirror.recordingFolder"
    static let wirelessEndpoint = "MotoMirror.wirelessEndpoint"
    static let wirelessSerial = "MotoMirror.wirelessSerial"
    static let preset = "MotoMirror.preset"
    static let usbOnly = "MotoMirror.usbOnly"
}

// MARK: - Log entries

enum AppLogLevel: String, Sendable {
    case info
    case success
    case warning
    case error
}

struct AppLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: AppLogLevel
    let source: String
    let message: String
}

// MARK: - Agent actions

enum AgentAction {
    case dumpUI
    case wake
    case typeText(String)
    case launch(String)
    case stop(String)
}

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {
    // Devices
    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var selectedSerial: String?
    @Published private(set) var details: DeviceDetails?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    // Mirror
    @Published var preset: MirrorPreset {
        didSet { presetDidChange(from: oldValue) }
    }
    @Published var options: ScrcpyOptions {
        didSet { optionsDidChange(from: oldValue) }
    }
    @Published private(set) var status = ScrcpyStatus()
    @Published private(set) var isReconnecting = false
    @Published private(set) var reconnectAttempt = 0
    @Published private(set) var isWaitingForDevice = false
    @Published private(set) var mirroringSerial: String?
    @Published private(set) var mirroringDeviceName: String?
    @Published private(set) var screenshotURL: URL?
    @Published private(set) var recordingURL: URL?

    // Wireless
    @Published private(set) var isDiscoveringWireless = false
    @Published private(set) var wirelessDiscoveryMessage: String?
    @Published private(set) var storedWirelessEndpoint: WirelessEndpoint?

    // Tailscale
    @Published private(set) var tailscalePeers: [TailscalePeer] = []
    @Published private(set) var isDiscoveringTailscale = false
    @Published private(set) var tailscaleMessage: String?

    // Agent
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = false
    @Published private(set) var agentMessage: String?
    @Published var isShowingAgentPanel = false
    @Published var usbOnly: Bool {
        didSet {
            guard !isDemoMode else { return }
            UserDefaults.standard.set(usbOnly, forKey: MMDefaults.usbOnly)
        }
    }

    // Tools
    @Published private(set) var toolchain: Toolchain?
    @Published private(set) var toolVersionSummary: String?

    // Activity
    @Published private(set) var logs: [AppLogEntry] = []
    @Published var errorMessage: String?
    @Published private(set) var isPairing = false
    @Published var isShowingWirelessSheet = false
    @Published var isShowingSetup = false
    @Published var recordingFolder: String {
        didSet {
            guard !isDemoMode else { return }
            UserDefaults.standard.set(recordingFolder, forKey: MMDefaults.recordingFolder)
        }
    }

    // Dependencies
    private var adb: any ADBServicing
    private var scrcpy: any ScrcpyControlling
    private var deviceActions: DeviceActions?
    let isDemoMode: Bool
    private let policy = ReconnectPolicy()

    // Tasks
    private var pollTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var hasStarted = false
    private var autoStartPending = false
    private var hasHandledInitialRefresh = false
    private var terminationSignalMonitor: TerminationSignalMonitor?
    private var isShuttingDown = false

    // Session bookkeeping
    private var userWantsMirroring = false
    private var hasUserStopped = false
    private var runningSince: Date?
    private var activeRecordingURL: URL?
    private var controllerLogCount = 0
    private var lastDetailsRefresh: Date?
    private var lastPollError: String?
    private var lastDetailsError: String?
    private var lastWirelessConnectAttempt: Date?
    private var preferredInitialSerial: String?
    private var storedWirelessSerial: String?
    private var wirelessEndpointCache: [String: WirelessEndpoint] = [:]
    private var mirroringModel: String?
    private var mirroringProduct: String?
    private var isApplyingPreset = false

    init(
        adb: any ADBServicing,
        scrcpy: any ScrcpyControlling,
        toolchain: Toolchain?,
        demoMode: Bool = false,
        options: ScrcpyOptions? = nil,
        recordingFolder: String? = nil
    ) {
        self.adb = adb
        self.scrcpy = scrcpy
        self.toolchain = toolchain
        self.isDemoMode = demoMode

        let defaults = UserDefaults.standard
        self.usbOnly = demoMode ? false : defaults.bool(forKey: MMDefaults.usbOnly)
        let storedPreset = defaults
            .string(forKey: MMDefaults.preset)
            .flatMap(MirrorPreset.init(rawValue:))
        let storedOptions = Self.loadOptions()

        let initialPreset: MirrorPreset
        let initialOptions: ScrcpyOptions
        let shouldMigrate: Bool

        if demoMode {
            initialPreset = .balanced
            initialOptions = options ?? MirrorPreset.balanced.options ?? .default
            shouldMigrate = false
        } else if let storedPreset {
            initialPreset = storedPreset
            initialOptions = storedPreset.options ?? options ?? storedOptions
            shouldMigrate = false
        } else {
            initialPreset = .balanced
            initialOptions = MirrorPreset.balanced.options ?? options ?? storedOptions
            shouldMigrate = true
        }

        self.preset = initialPreset
        self.options = initialOptions
        self.recordingFolder = recordingFolder
            ?? defaults.string(forKey: MMDefaults.recordingFolder)
            ?? ""
        self.storedWirelessEndpoint = demoMode ? nil : Self.loadWirelessEndpoint()
        self.storedWirelessSerial = demoMode ? nil : defaults.string(forKey: MMDefaults.wirelessSerial)

        if shouldMigrate {
            defaults.set(MirrorPreset.balanced.rawValue, forKey: MMDefaults.preset)
            if let data = try? JSONEncoder().encode(initialOptions) {
                defaults.set(data, forKey: MMDefaults.options)
            }
            let message = "Preset migrated to Balanced to reduce battery use"
            appendLog(message, level: .info)
            FileHandle.standardOutput.write(Data((message + "\n").utf8))
        }
    }

    // MARK: - Factories

    static func live() -> AppModel {
        let defaults = UserDefaults.standard
        let adbOverride = defaults.string(forKey: MMDefaults.adbPath)
        let scrcpyOverride = defaults.string(forKey: MMDefaults.scrcpyPath)
        let toolchain = BinaryLocator.toolchain(
            adbOverride: adbOverride,
            scrcpyOverride: scrcpyOverride
        )
        let recordingFolder = defaults.string(forKey: MMDefaults.recordingFolder) ?? ""

        if let toolchain {
            let runner = ProcessRunner()
            let model = AppModel(
                adb: ADBClient(adbURL: toolchain.adb, runner: runner),
                scrcpy: ScrcpyController(
                    scrcpyURL: toolchain.scrcpy,
                    adbURL: toolchain.adb,
                    runner: runner
                ),
                toolchain: toolchain,
                demoMode: false,
                recordingFolder: recordingFolder
            )
            model.deviceActions = DeviceActions(adbURL: toolchain.adb, runner: runner)
            return model
        }

        return AppModel(
            adb: UnavailableADBService(),
            scrcpy: UnavailableScrcpyService(),
            toolchain: nil,
            demoMode: false,
            recordingFolder: recordingFolder
        )
    }

    static func demo(scenario: DemoScenario = .connected) -> AppModel {
        let demoADB = DemoADBService(scenario: scenario)
        let demoSrcpy = DemoScrcpyService()
        let toolchain: Toolchain? = scenario == .setup
            ? nil
            : Toolchain(
                adb: URL(fileURLWithPath: "/opt/homebrew/bin/adb"),
                scrcpy: URL(fileURLWithPath: "/opt/homebrew/bin/scrcpy"),
                ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            )
        let model = AppModel(
            adb: demoADB,
            scrcpy: demoSrcpy,
            toolchain: toolchain,
            demoMode: true,
            recordingFolder: ""
        )

        model.devices = demoADB.previewDevices
        if let toolchain {
            model.deviceActions = DeviceActions(adbURL: toolchain.adb)
        }
        model.toolVersionSummary = toolchain == nil ? nil : "adb 37.0.2 · scrcpy 5.0.1"
        model.lastRefresh = Date()

        switch scenario {
        case .connected:
            model.selectedSerial = DemoData.phoneSerial
            model.details = demoADB.previewDetails(for: DemoData.phoneSerial)
        case .unauthorized:
            model.selectedSerial = DemoData.phoneSerial
            model.details = nil
        case .empty, .setup:
            model.selectedSerial = nil
            model.details = nil
        }

        model.seedLogs(for: scenario)
        return model
    }

    // MARK: - Derived state

    var selectedDevice: AndroidDevice? {
        guard let selectedSerial else { return nil }
        return devices.first { $0.serial == selectedSerial }
    }

    private var mirroringDevice: AndroidDevice? {
        guard let mirroringSerial else { return nil }
        return devices.first { $0.serial == mirroringSerial }
    }

    private var isMirroringWireless: Bool {
        guard let mirroringSerial else { return false }
        return isWirelessSerial(mirroringSerial)
    }

    private var hasWirelessRecoveryHint: Bool {
        storedWirelessEndpoint != nil || (storedWirelessSerial.map(isWirelessSerial) ?? false)
    }

    var isWaitingForMirrorDevice: Bool {
        (isWaitingForDevice || isReconnecting) && mirroringSerial != nil && selectedDevice == nil
    }

    var reconnectAttemptLimit: Int { policy.maxAttempts }

    var isMirroring: Bool { status.isActive }

    var isRecovering: Bool { isReconnecting || isWaitingForDevice }

    var canStartMirroring: Bool {
        toolchain != nil && selectedDevice?.isUsable == true && !status.isActive
    }

    var canUseSelectedDevice: Bool {
        selectedDevice?.isUsable == true
    }

    var toolsReady: Bool { toolchain != nil }

    var recordingFolderURL: URL {
        let trimmed = recordingFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return URL(
                fileURLWithPath: (trimmed as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        return movies.appendingPathComponent("MotoMirror", isDirectory: true)
    }

    var recordingFolderDisplayPath: String {
        recordingFolderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var screenshotFolderURL: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("MotoMirror", isDirectory: true)
    }

    var mirrorButtonTitle: String {
        if isRecovering { return "Stop Reconnecting" }
        switch status.state {
        case .starting: return "Starting…"
        case .running: return "Stop Mirroring"
        case .stopping: return "Stopping…"
        default: return "Start Mirroring"
        }
    }

    var mirrorStatusText: String {
        switch status.state {
        case .idle: return "Ready"
        case .starting: return "Starting"
        case .running: return "Mirroring"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        case .failed: return "Mirror failed"
        }
    }

    // MARK: - Lifecycle

    /// Arms the non-interactive `--auto-mirror` / `MOTOMIRROR_AUTOSTART=1`
    /// hook. The first successful device refresh decides whether to start.
    func enableAutoMirror() {
        guard toolchain != nil else {
            appendLog("AUTO-START skipped: adb or scrcpy is missing.", level: .warning)
            return
        }
        guard !autoStartPending, !hasHandledInitialRefresh else { return }
        autoStartPending = true
        appendLog("AUTO-START armed; waiting for the first device refresh.", level: .info)
    }

    /// Used by `--select-serial` / `MOTOMIRROR_SELECT_SERIAL` for automated
    /// verification. The preference is applied once, when the serial appears.
    func preferInitialSerial(_ serial: String?) {
        let trimmed = serial?.trimmingCharacters(in: .whitespacesAndNewlines)
        preferredInitialSerial = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard toolchain != nil else {
            appendLog("adb and scrcpy were not found on this Mac.", level: .warning)
            appendLog("Open Setup & Help to install both tools.", level: .info)
            return
        }
        if isDemoMode {
            Task { await loadToolVersions(); await refreshDevices() }
            return
        }
        startPollingIfNeeded()
    }

    /// Installs signal handling for non-interactive stops (`kill -TERM`,
    /// `kill -INT`). The signal handler routes back to the main actor so it can
    /// use the same shutdown path as Cmd+Q.
    func installSignalHandlers() {
        guard terminationSignalMonitor == nil else { return }
        let monitor = TerminationSignalMonitor { [weak self] signalNumber in
            Task { @MainActor in
                self?.handleTerminationSignal(signalNumber)
            }
        }
        terminationSignalMonitor = monitor
        monitor.install()
    }

    private func handleTerminationSignal(_ signalNumber: Int32) {
        let name = signalNumber == SIGTERM ? "SIGTERM" : "SIGINT"
        let line = "\(name) received; stopping scrcpy before exit."
        appendLog(line, level: .warning)
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
        shutdown()
        exit(0)
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        pollTask?.cancel()
        pollTask = nil
        statusTask?.cancel()
        statusTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        // App termination tears the process down immediately after this
        // notification, so wait here for the controller's SIGTERM/SIGKILL
        // cleanup instead of leaving an orphaned scrcpy process behind.
        let controller = scrcpy
        let finished = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await controller.stop()
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + 5)
    }

    private func startPollingIfNeeded() {
        guard !isDemoMode, toolchain != nil, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.loadToolVersions()
            while !Task.isCancelled {
                await self.refreshDevices()
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    // MARK: - Tool discovery

    func loadToolVersions() async {
        guard toolchain != nil else {
            toolVersionSummary = nil
            return
        }
        do {
            async let adbVersion = adb.version()
            async let scrcpyVersion = scrcpy.version()
            let (adbText, scrcpyText) = try await (adbVersion, scrcpyVersion)
            toolVersionSummary = "\(Self.shortVersion(adbText, name: "adb")) · \(Self.shortVersion(scrcpyText, name: "scrcpy"))"
        } catch {
            toolVersionSummary = "adb · scrcpy"
            appendLog("Could not read tool versions: \(Self.friendlyMessage(for: error))", level: .warning)
        }
    }

    func detectToolchain() {
        guard !isDemoMode else {
            appendLog("Demo mode uses simulated tools.", level: .info)
            return
        }
        guard !status.isActive else {
            errorMessage = "Stop mirroring before changing the tool paths."
            return
        }
        let defaults = UserDefaults.standard
        let found = BinaryLocator.toolchain(
            adbOverride: defaults.string(forKey: MMDefaults.adbPath),
            scrcpyOverride: defaults.string(forKey: MMDefaults.scrcpyPath)
        )
        toolchain = found
        errorMessage = nil
        toolVersionSummary = nil

        if let found {
            let runner = ProcessRunner()
            adb = ADBClient(adbURL: found.adb, runner: runner)
            scrcpy = ScrcpyController(
                scrcpyURL: found.scrcpy,
                adbURL: found.adb,
                runner: runner
            )
            appendLog("adb and scrcpy found.", level: .success)
            Task {
                await loadToolVersions()
                await refreshDevices()
            }
            startPollingIfNeeded()
        } else {
            pollTask?.cancel()
            pollTask = nil
            adb = UnavailableADBService()
            scrcpy = UnavailableScrcpyService()
            devices = []
            selectedSerial = nil
            details = nil
            lastRefresh = nil
            appendLog("adb or scrcpy is still missing. Follow the setup steps below.", level: .warning)
        }
    }

    func applyToolPaths(adbPath: String, scrcpyPath: String) {
        guard !isDemoMode else {
            appendLog("Tool paths are fixed in demo mode.", level: .info)
            return
        }
        guard !status.isActive else {
            errorMessage = "Stop mirroring before changing the tool paths."
            return
        }
        let defaults = UserDefaults.standard
        let trimmedADB = adbPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScrcpy = scrcpyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedADB.isEmpty {
            defaults.removeObject(forKey: MMDefaults.adbPath)
        } else {
            defaults.set(trimmedADB, forKey: MMDefaults.adbPath)
        }
        if trimmedScrcpy.isEmpty {
            defaults.removeObject(forKey: MMDefaults.scrcpyPath)
        } else {
            defaults.set(trimmedScrcpy, forKey: MMDefaults.scrcpyPath)
        }
        detectToolchain()
    }

    func resetAllSettings() {
        guard !isDemoMode else {
            appendLog("Settings reset is disabled in demo mode.", level: .info)
            return
        }
        guard !status.isActive else {
            errorMessage = "Stop mirroring before resetting settings."
            return
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: MMDefaults.options)
        defaults.removeObject(forKey: MMDefaults.preset)
        defaults.removeObject(forKey: MMDefaults.adbPath)
        defaults.removeObject(forKey: MMDefaults.scrcpyPath)
        defaults.removeObject(forKey: MMDefaults.recordingFolder)
        defaults.removeObject(forKey: MMDefaults.wirelessEndpoint)
        defaults.removeObject(forKey: MMDefaults.wirelessSerial)
        defaults.removeObject(forKey: MMDefaults.usbOnly)
        usbOnly = false

        let balancedOptions = MirrorPreset.balanced.options ?? .default
        isApplyingPreset = true
        preset = .balanced
        options = balancedOptions
        isApplyingPreset = false

        recordingFolder = ""
        storedWirelessEndpoint = nil
        storedWirelessSerial = nil
        lastWirelessConnectAttempt = nil
        errorMessage = nil
        appendLog("Settings reset to defaults.", level: .info)
        detectToolchain()
    }

    // MARK: - Polling

    func refreshNow() {
        Task { await refreshDevices() }
    }

    func refreshDevices() async {
        guard toolchain != nil else {
            devices = []
            selectedSerial = nil
            details = nil
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var found = try await adb.devices()

            if found.isEmpty,
               !usbOnly,
               hasWirelessRecoveryHint,
               shouldAttemptBackgroundWirelessRecovery {
                lastWirelessConnectAttempt = Date()
                if let endpoint = storedWirelessEndpoint {
                    _ = await connectWirelessEndpoint(
                        endpoint,
                        reason: "background recovery"
                    )
                }
                appendLog("WIRELESS: background mDNS refresh…", level: .info)
                let services = (try? await adb.mdnsServices()) ?? []
                appendLog(
                    "WIRELESS: background mDNS returned \(services.count) service(s).",
                    level: services.isEmpty ? .warning : .info
                )
                if let refreshed = try? await adb.devices() {
                    found = refreshed
                }
            }

            if usbOnly {
                found = found.filter { $0.transport == .usb }
            }
            let normalized = DeviceListNormalizer.normalize(found)
            updateWirelessEndpointCache(raw: found, normalized: normalized)
            let sorted = normalized.sorted { lhs, rhs in
                if lhs.isUsable != rhs.isUsable { return lhs.isUsable }
                if lhs.transport != rhs.transport { return lhs.transport == .usb }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            devices = sorted
            lastRefresh = Date()
            lastPollError = nil
            reconcileSelection()
            handleAutoStartAfterRefresh()

            if let device = selectedDevice, let serial = selectedSerial {
                if device.isUsable {
                    let stale = details?.serial != serial
                        || Date().timeIntervalSince(lastDetailsRefresh ?? .distantPast) > 5
                    if stale {
                        await refreshDetails(for: serial)
                    }
                } else {
                    details = nil
                }
            } else if selectedDevice == nil {
                details = nil
            }

            attemptAutomaticReconnectIfNeeded()
        } catch {
            let message = Self.friendlyMessage(for: error)
            if lastPollError != message {
                lastPollError = message
                appendLog("Device scan failed: \(message)", level: .warning)
            }
        }
    }

    func select(_ serial: String?) {
        guard serial != selectedSerial else { return }
        selectedSerial = serial
        details = nil
        lastDetailsError = nil
        lastDetailsRefresh = nil

        guard let serial, let device = devices.first(where: { $0.serial == serial }) else {
            return
        }
        appendLog("Selected \(device.displayName) over \(device.mmTransportLabel).", level: .info)
        guard device.isUsable else { return }
        Task { await refreshDetails(for: serial) }
    }

    private func reconcileSelection() {
        if let preferredSerial = preferredInitialSerial {
            preferredInitialSerial = nil
            if let device = devices.first(where: { $0.serial == preferredSerial }) {
                if selectedSerial != preferredSerial {
                    selectedSerial = preferredSerial
                    details = nil
                    lastDetailsRefresh = nil
                    lastDetailsError = nil
                    appendLog(
                        "Selected \(device.displayName) over \(device.mmTransportLabel) from the launch request.",
                        level: .info
                    )
                }
                return
            }
        }

        if let selectedSerial, devices.contains(where: { $0.serial == selectedSerial }) {
            return
        }
        if userWantsMirroring,
           !hasUserStopped,
           let mirroringSerial,
           selectedSerial == mirroringSerial {
            // Keep the mirrored phone selected while it is briefly away so the
            // reconnect flow has a stable target and the sidebar does not jump
            // to a different device.
            return
        }
        let previous = selectedSerial
        if let firstUsable = devices.first(where: { $0.isUsable }) {
            selectedSerial = firstUsable.serial
        } else if let first = devices.first {
            selectedSerial = first.serial
        } else {
            selectedSerial = nil
            details = nil
        }

        if previous != selectedSerial, let device = selectedDevice, previous != nil {
            appendLog("Selected \(device.displayName) over \(device.mmTransportLabel).", level: .info)
        } else if previous != selectedSerial, let device = selectedDevice {
            appendLog("Found \(device.displayName) over \(device.mmTransportLabel).", level: .success)
        }
    }

    private func handleAutoStartAfterRefresh() {
        guard autoStartPending, !hasHandledInitialRefresh else { return }
        hasHandledInitialRefresh = true
        autoStartPending = false

        guard toolchain != nil else {
            emitAutoStart("AUTO-START skipped: adb or scrcpy is missing.", level: .warning)
            return
        }
        guard !status.isActive else {
            emitAutoStart("AUTO-START skipped: a mirror session is already active.", level: .info)
            return
        }
        guard let device = selectedDevice else {
            emitAutoStart("AUTO-START skipped: no device is connected.", level: .warning)
            return
        }
        guard device.isUsable else {
            emitAutoStart(
                "AUTO-START skipped: \(device.displayName) is \(device.mmStateLabel.lowercased()).",
                level: .warning
            )
            return
        }

        emitAutoStart(
            "AUTO-START: starting mirroring for \(device.displayName) (\(device.serial)) over \(device.mmTransportLabel).",
            level: .success
        )
        startMirroring()
    }

    /// Writes the AUTO-START decision to the in-app session log and to stdout,
    /// so a non-interactive verifier can read it from the launch log too.
    private func emitAutoStart(_ message: String, level: AppLogLevel) {
        appendLog(message, level: level)
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func refreshDetails(for serial: String) async {
        do {
            let loaded = try await adb.details(for: serial)
            guard selectedSerial == serial else { return }
            details = loaded
            lastDetailsRefresh = Date()
            lastDetailsError = nil
        } catch {
            guard selectedSerial == serial else { return }
            details = nil
            lastDetailsRefresh = Date()
            let message = Self.friendlyMessage(for: error)
            if lastDetailsError != message {
                lastDetailsError = message
                if let mirrorError = error as? MotoMirrorError,
                   case .deviceUnauthorized = mirrorError {
                    appendLog("\(selectedDevice?.displayName ?? serial) is waiting for USB debugging authorization.", level: .warning)
                } else if let mirrorError = error as? MotoMirrorError,
                          case .deviceNotFound = mirrorError {
                    appendLog("\(selectedDevice?.displayName ?? serial) is no longer connected.", level: .info)
                } else {
                    appendLog("Could not refresh phone details: \(message)", level: .warning)
                }
            }
        }
    }

    // MARK: - Mirroring

    func toggleMirroring() {
        if status.isActive || isReconnecting || isWaitingForDevice {
            stopMirroring()
        } else {
            startMirroring()
        }
    }

    func startMirroring() {
        guard !status.isActive else { return }
        guard let device = selectedDevice else {
            errorMessage = "Select a phone from the sidebar first."
            return
        }
        guard device.isUsable else {
            if device.state == .unauthorized {
                errorMessage = "Authorize this phone before mirroring. Unlock it and accept the USB debugging prompt."
            } else {
                errorMessage = "\(device.displayName) is not ready. Reconnect it and refresh."
            }
            return
        }
        guard toolchain != nil else {
            errorMessage = "Install adb and scrcpy before mirroring."
            isShowingSetup = true
            return
        }

        hasUserStopped = false
        userWantsMirroring = true
        mirroringSerial = device.serial
        mirroringDeviceName = device.displayName
        mirroringModel = device.model
        mirroringProduct = device.product
        isReconnecting = false
        isWaitingForDevice = false
        reconnectAttempt = 0
        errorMessage = nil

        var recordURL: URL?
        if options.recordEnabled {
            guard let made = makeRecordingURL(serial: device.serial) else {
                userWantsMirroring = false
                mirroringSerial = nil
                mirroringDeviceName = nil
                mirroringModel = nil
                mirroringProduct = nil
                return
            }
            recordURL = made
        }
        activeRecordingURL = recordURL
        if let recordURL { recordingURL = recordURL }

        appendLog("Starting mirroring for \(device.displayName)…", level: .info)
        Task {
            await launchMirror(serial: device.serial, recordURL: recordURL, isReconnect: false)
        }
    }

    func stopMirroring() {
        guard status.isActive || userWantsMirroring || isReconnecting else { return }
        hasUserStopped = true
        userWantsMirroring = false
        mirroringSerial = nil
        mirroringDeviceName = nil
        mirroringModel = nil
        mirroringProduct = nil
        isReconnecting = false
        isWaitingForDevice = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        appendLog("Stopping mirroring…", level: .info)

        Task {
            await scrcpy.stop()
            let newStatus = await scrcpy.status()
            let controllerLogs = await scrcpy.logs()
            ingest(status: newStatus, controllerLogs: controllerLogs)
            statusTask?.cancel()
            statusTask = nil
            appendLog("Mirroring stopped.", level: .success)
            if let activeRecordingURL {
                let exists = FileManager.default.fileExists(atPath: activeRecordingURL.path)
                if exists {
                    appendLog("Recording saved to \(activeRecordingURL.path)", level: .success)
                }
            }
            activeRecordingURL = nil
        }
    }

    private func launchMirror(serial: String, recordURL: URL?, isReconnect: Bool) async {
        status = ScrcpyStatus(state: .starting)
        if let recordURL {
            appendLog("Recording video to \(recordURL.path)", level: .info)
        }
        if isWirelessSerial(serial) {
            rememberWirelessSerial(serial)
            if let endpoint = WirelessEndpoint(serial: serial) ?? wirelessEndpointCache[serial] {
                rememberWirelessEndpoint(endpoint)
            }
        }
        do {
            var sessionOptions = options
            if let displayName = devices.first(where: { $0.serial == serial })?.displayName,
               !displayName.isEmpty {
                sessionOptions.extraArguments.append(
                    "--window-title=\(sessionOptions.windowTitle(deviceName: displayName))"
                )
            }
            try await scrcpy.start(serial: serial, options: sessionOptions, recordPath: recordURL?.path)
            if hasUserStopped {
                await scrcpy.stop()
                status = await scrcpy.status()
                return
            }
            let newStatus = await scrcpy.status()
            let controllerLogs = await scrcpy.logs()
            ingest(status: newStatus, controllerLogs: controllerLogs)

            if newStatus.isActive {
                startStatusMonitor()
                isReconnecting = false
                isWaitingForDevice = false
                errorMessage = nil
                if isReconnect {
                    appendLog("Mirror session restored.", level: .success)
                } else {
                    appendLog("Mirroring started.", level: .success)
                }
            } else if newStatus.state == .failed {
                let message = newStatus.message ?? "scrcpy could not start."
                errorMessage = message
                appendLog("Mirror start failed: \(message)", level: .error)
                if !isReconnect {
                    userWantsMirroring = false
                    mirroringSerial = nil
                    mirroringDeviceName = nil
                    mirroringModel = nil
                    mirroringProduct = nil
                }
            }
        } catch {
            let message = Self.friendlyMessage(for: error)
            status = ScrcpyStatus(state: .failed, message: message)
            errorMessage = message
            appendLog("Mirror start failed: \(message)", level: .error)
            isReconnecting = false
            await mergeControllerLogs()
            if !isReconnect {
                userWantsMirroring = false
                mirroringSerial = nil
                mirroringDeviceName = nil
                mirroringModel = nil
                mirroringProduct = nil
            }
        }
    }

    private func startStatusMonitor() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let newStatus = await self.scrcpy.status()
                let controllerLogs = await self.scrcpy.logs()
                self.ingest(status: newStatus, controllerLogs: controllerLogs)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func ingest(status newStatus: ScrcpyStatus, controllerLogs: [String]) {
        mergeControllerLogs(controllerLogs)
        let previous = status
        status = newStatus

        switch newStatus.state {
        case .running:
            if runningSince == nil { runningSince = Date() }
            if let runningSince, Date().timeIntervalSince(runningSince) > 15 {
                reconnectAttempt = 0
                isReconnecting = false
            }
            isWaitingForDevice = false
        default:
            runningSince = nil
        }

        guard previous.isActive && !newStatus.isActive else { return }
        guard userWantsMirroring, !hasUserStopped else { return }

        if newStatus.state == .failed {
            let message = newStatus.message ?? "scrcpy stopped unexpectedly."
            appendLog(message, level: .error)
            if errorMessage == nil { errorMessage = message }
        } else {
            appendLog("Mirroring stopped unexpectedly.", level: .warning)
        }
        handleUnexpectedStop()
    }

    private func handleUnexpectedStop() {
        guard userWantsMirroring, !hasUserStopped else { return }
        let device = mirroringDevice
        if let device, device.isUsable {
            scheduleReconnectIfPossible()
        } else if isMirroringWireless {
            appendLog("Wireless connection dropped; trying to reconnect…", level: .info)
            scheduleReconnectIfPossible()
        } else {
            isReconnecting = false
            isWaitingForDevice = true
            appendLog(
                "Waiting for \(mirroringDeviceName ?? device?.displayName ?? "the phone") to reconnect…",
                level: .info
            )
        }
    }

    private func attemptAutomaticReconnectIfNeeded() {
        guard userWantsMirroring,
              !hasUserStopped,
              !status.isActive,
              !isReconnecting,
              reconnectTask == nil,
              let mirroringSerial
        else {
            return
        }
        let device = devices.first(where: { $0.serial == mirroringSerial && $0.isUsable })
        guard device != nil || isMirroringWireless else {
            return
        }
        if let device, selectedSerial != device.serial {
            select(device.serial)
        }
        if isWaitingForDevice, let device {
            appendLog("\(device.displayName) is back. Restoring the mirror…", level: .info)
            isWaitingForDevice = false
        }
        scheduleReconnectIfPossible()
    }

    private func scheduleReconnectIfPossible() {
        guard reconnectTask == nil else { return }
        let device = mirroringDevice
        let devicePresent = device?.isUsable == true || isMirroringWireless
        let stopped = hasUserStopped || !userWantsMirroring

        guard policy.shouldRetry(
            attempt: reconnectAttempt,
            devicePresent: devicePresent,
            userStopped: stopped
        ) else {
            if !stopped && !devicePresent {
                isWaitingForDevice = true
                return
            }
            if !stopped && reconnectAttempt >= policy.maxAttempts {
                userWantsMirroring = false
                mirroringSerial = nil
                mirroringDeviceName = nil
                mirroringModel = nil
                mirroringProduct = nil
                isReconnecting = false
                isWaitingForDevice = false
                statusTask?.cancel()
                statusTask = nil
                appendLog(
                    "Automatic reconnect stopped after \(policy.maxAttempts) attempts. Start mirroring again when the phone is ready.",
                    level: .warning
                )
            }
            return
        }

        let nextAttempt = reconnectAttempt + 1
        reconnectAttempt = nextAttempt
        isReconnecting = true
        isWaitingForDevice = false
        let delay = policy.delay(forAttempt: nextAttempt)
        let deviceName = mirroringDeviceName ?? device?.displayName ?? "your phone"
        appendLog(
            "Reconnecting to \(deviceName) in \(Self.delayLabel(delay)) (attempt \(nextAttempt) of \(policy.maxAttempts))…",
            level: .warning
        )

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.performReconnect()
            self.reconnectTask = nil
            if self.userWantsMirroring,
               !self.hasUserStopped,
               !self.status.isActive,
               self.reconnectTask == nil {
                self.scheduleReconnectIfPossible()
            }
        }
    }

    private func resolveMirroringDevice(exact serial: String) -> AndroidDevice? {
        if let exact = devices.first(where: { $0.serial == serial && $0.isUsable }) {
            return exact
        }
        if let storedWirelessSerial,
           let stored = devices.first(where: { $0.serial == storedWirelessSerial && $0.isUsable }) {
            return stored
        }
        guard isWirelessSerial(serial) else { return nil }

        let candidates = devices.filter { $0.isUsable && isWirelessSerial($0.serial) }
        if candidates.count == 1 {
            return candidates[0]
        }

        let identityMatches = candidates.filter { candidate in
            let modelMatches = normalizedIdentity(candidate.model) != nil
                && normalizedIdentity(candidate.model) == normalizedIdentity(mirroringModel)
            let productMatches = normalizedIdentity(candidate.product) != nil
                && normalizedIdentity(candidate.product) == normalizedIdentity(mirroringProduct)
            return modelMatches || productMatches
        }
        return identityMatches.count == 1 ? identityMatches[0] : nil
    }

    private func performReconnect() async {
        guard userWantsMirroring, !hasUserStopped else {
            isReconnecting = false
            return
        }
        guard toolchain != nil else {
            userWantsMirroring = false
            mirroringSerial = nil
            mirroringDeviceName = nil
            mirroringModel = nil
            mirroringProduct = nil
            isReconnecting = false
            appendLog("Cannot reconnect because adb or scrcpy is missing.", level: .error)
            return
        }
        guard let serial = mirroringSerial else {
            isReconnecting = false
            isWaitingForDevice = true
            return
        }

        var device = resolveMirroringDevice(exact: serial)

        // Give adb a chance to restore the stable mDNS serial first.
        if device == nil {
            await waitForRefreshToFinish()
            await refreshDevices()
            device = resolveMirroringDevice(exact: serial)
        }

        // If it is still gone, ask adb's mDNS responder to repopulate the
        // stable serial, then refresh once more.
        if device == nil, isWirelessSerial(serial) {
            appendLog("WIRELESS: asking adb for mDNS services…", level: .info)
            let services = (try? await adb.mdnsServices()) ?? []
            appendLog(
                "WIRELESS: mDNS returned \(services.count) service(s).",
                level: services.isEmpty ? .warning : .info
            )
            await waitForRefreshToFinish()
            await refreshDevices()
            device = resolveMirroringDevice(exact: serial)
        }

        // Last resort: reconnect the stored host:port endpoint.
        if device == nil, isWirelessSerial(serial), let endpoint = storedWirelessEndpoint {
            _ = await connectWirelessEndpoint(endpoint, reason: "reconnect fallback")
            await waitForRefreshToFinish()
            await refreshDevices()
            device = resolveMirroringDevice(exact: serial)
        }

        guard let device else {
            isReconnecting = false
            isWaitingForDevice = true
            appendLog(
                "\(mirroringDeviceName ?? "The phone") is still unavailable; waiting for it to return…",
                level: .info
            )
            return
        }

        if device.serial != serial {
            appendLog("WIRELESS: using normalized serial \(device.serial).", level: .info)
        }
        mirroringSerial = device.serial
        mirroringDeviceName = device.displayName
        mirroringModel = device.model
        mirroringProduct = device.product
        if isWirelessSerial(device.serial) {
            rememberWirelessSerial(device.serial)
        }

        isReconnecting = true
        var recordURL: URL?
        if options.recordEnabled {
            recordURL = makeRecordingURL(serial: device.serial)
            if recordURL == nil {
                appendLog("Recording could not restart; reconnecting without recording.", level: .warning)
            }
        }
        activeRecordingURL = recordURL
        if let recordURL { recordingURL = recordURL }
        appendLog("Reconnecting now…", level: .info)
        await launchMirror(serial: device.serial, recordURL: recordURL, isReconnect: true)
    }

    private func waitForRefreshToFinish() async {
        let deadline = Date().addingTimeInterval(5)
        while isRefreshing && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private var shouldAttemptBackgroundWirelessRecovery: Bool {
        guard hasWirelessRecoveryHint else { return false }
        guard let lastWirelessConnectAttempt else { return true }
        return Date().timeIntervalSince(lastWirelessConnectAttempt) > 10
    }

    @discardableResult
    private func connectWirelessEndpoint(
        _ endpoint: WirelessEndpoint,
        reason: String
    ) async -> Bool {
        lastWirelessConnectAttempt = Date()
        appendLog("WIRELESS: \(reason) to \(endpoint.serial)…", level: .info)
        do {
            let message = try await adb.connect(host: endpoint.host, port: endpoint.port)
            appendLog("WIRELESS: \(reason) connected: \(message)", level: .success)
            return true
        } catch {
            appendLog(
                "WIRELESS: \(reason) failed for \(endpoint.serial): \(Self.friendlyMessage(for: error))",
                level: .warning
            )
            return false
        }
    }

    // MARK: - Agent tools

    func loadInstalledApps(includeSystem: Bool) async {
        guard let serial = selectedDevice?.serial, let actions = deviceActions else {
            agentMessage = "Select a phone first."
            installedApps = []
            return
        }
        isLoadingApps = true
        defer { isLoadingApps = false }
        do {
            installedApps = try await actions.packages(serial: serial, includeSystem: includeSystem)
            agentMessage = "\(installedApps.count) packages"
        } catch {
            installedApps = []
            agentMessage = Self.friendlyMessage(for: error)
        }
    }

    func runAgentAction(_ action: AgentAction) async {
        guard let serial = selectedDevice?.serial, let actions = deviceActions else {
            agentMessage = "Select a phone first."
            return
        }
        do {
            switch action {
            case .dumpUI:
                let hierarchy = try await actions.hierarchy(serial: serial)
                agentMessage = "UI hierarchy: \(hierarchy.elements.count) elements"
            case .wake:
                try await actions.wake(serial: serial)
                agentMessage = "Screen awake"
            case .typeText(let text):
                try await actions.inputText(serial: serial, text: text)
                agentMessage = "Typed text"
            case .launch(let package):
                _ = try await actions.launchApp(serial: serial, package: package)
                agentMessage = "Launched \(package)"
            case .stop(let package):
                try await actions.stopApp(serial: serial, package: package)
                agentMessage = "Stopped \(package)"
            }
        } catch {
            agentMessage = Self.friendlyMessage(for: error)
        }
    }

    func loadLogcat(lines: Int) async -> [String] {
        guard let serial = selectedDevice?.serial, let actions = deviceActions else {
            return []
        }
        do {
            let output = try await actions.logcat(serial: serial, lines: lines)
            return output.split(whereSeparator: \.isNewline).map(String.init)
        } catch {
            agentMessage = Self.friendlyMessage(for: error)
            return []
        }
    }

    // MARK: - Screenshot and recording

    func takeScreenshot() {
        guard let device = selectedDevice, device.isUsable else {
            errorMessage = "Connect and select a phone before taking a screenshot."
            return
        }
        guard toolchain != nil else {
            errorMessage = "Install adb before taking a screenshot."
            isShowingSetup = true
            return
        }
        let serial = device.serial
        appendLog("Capturing a screenshot from \(device.displayName)…", level: .info)

        Task {
            do {
                let data = try await adb.screenshot(serial: serial)
                guard !data.isEmpty else {
                    throw MotoMirrorError.parseFailure("The screenshot was empty.")
                }
                try FileManager.default.createDirectory(
                    at: screenshotFolderURL,
                    withIntermediateDirectories: true
                )
                let url = screenshotFolderURL
                    .appendingPathComponent("MotoMirror-\(Self.fileSafe(serial))-\(Self.fileStamp()).png")
                try data.write(to: url, options: .atomic)
                screenshotURL = url
                errorMessage = nil
                appendLog("Screenshot saved to \(url.path)", level: .success)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                let message = Self.friendlyMessage(for: error)
                errorMessage = message
                appendLog("Screenshot failed: \(message)", level: .error)
            }
        }
    }

    func revealScreenshot() {
        guard let screenshotURL,
              FileManager.default.fileExists(atPath: screenshotURL.path) else {
            errorMessage = "No screenshot has been saved yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([screenshotURL])
    }

    func revealRecording() {
        guard let recordingURL,
              FileManager.default.fileExists(atPath: recordingURL.path) else {
            if FileManager.default.fileExists(atPath: recordingFolderURL.path) {
                NSWorkspace.shared.open(recordingFolderURL)
            } else {
                errorMessage = "No recording has been saved yet."
            }
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([recordingURL])
    }

    func setRecordingFolder(_ path: String) {
        recordingFolder = path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Wireless

    func discoverTailscalePeers() async {
        guard !isDiscoveringTailscale else { return }
        isDiscoveringTailscale = true
        tailscaleMessage = nil
        defer { isDiscoveringTailscale = false }

        guard let cli = TailscaleDiscovery.locateCLI() else {
            tailscalePeers = []
            let message = "Install Tailscale on this Mac to use a phone over your tailnet."
            tailscaleMessage = message
            appendLog("TAILSCALE: \(message)", level: .warning)
            return
        }

        do {
            let peers = try await TailscaleDiscovery.status(using: cli)
            let androidPeers = TailscaleDiscovery.androidPeers(from: peers)
            tailscalePeers = androidPeers

            if androidPeers.isEmpty {
                let message = "No Android peers found. Install Tailscale on the phone and sign in to the same tailnet."
                tailscaleMessage = message
                appendLog("TAILSCALE: \(message)", level: .warning)
            } else {
                let onlineCount = androidPeers.filter(\.online).count
                let peerWord = androidPeers.count == 1 ? "peer" : "peers"
                let message = "Found \(androidPeers.count) Android \(peerWord) — \(onlineCount) online."
                tailscaleMessage = message
                appendLog("TAILSCALE: \(message)", level: .info)
            }
        } catch {
            tailscalePeers = []
            let message = "Could not read Tailscale status. Open Tailscale on this Mac and try again."
            tailscaleMessage = message
            appendLog(
                "TAILSCALE: \(Self.friendlyMessage(for: error))",
                level: .warning
            )
        }
    }

    func discoverWirelessEndpoint() async -> (host: String, pairingPort: Int?, connectPort: Int?)? {
        guard !isDiscoveringWireless else { return nil }
        guard toolchain != nil else {
            let message = "Wireless discovery needs adb. Install it from Setup & Help, then try again."
            wirelessDiscoveryMessage = message
            appendLog("WIRELESS: \(message)", level: .warning)
            return nil
        }

        isDiscoveringWireless = true
        wirelessDiscoveryMessage = nil
        defer { isDiscoveringWireless = false }

        do {
            let services = try await adb.mdnsServices()
            guard !services.isEmpty else {
                let message = "No wireless debugging service was advertised. Keep the phone unlocked, on this Wi-Fi network, and open Pair device with pairing code, then click Discover again."
                wirelessDiscoveryMessage = message
                appendLog("WIRELESS: discovery found no mDNS services.", level: .warning)
                return nil
            }

            let pairing = services.first { $0.kind == .pairing }
            let connect = services.first { $0.kind == .connect }
            guard pairing != nil || connect != nil else {
                let message = "The advertised services are not Android wireless debugging services. Check that the phone is on this Wi-Fi network and try again."
                wirelessDiscoveryMessage = message
                appendLog("WIRELESS: non-ADB services advertised: \(serviceSummary(services)).", level: .warning)
                return nil
            }
            // Both advert types carry the same phone host. Ports are kept
            // service-specific so a pairing attempt never uses the connect port.
            guard let host = pairing?.host ?? connect?.host, !host.isEmpty else {
                let message = "The wireless service was advertised without a usable host. Type the address shown on the phone instead."
                wirelessDiscoveryMessage = message
                appendLog("WIRELESS: advertised service is missing a host.", level: .warning)
                return nil
            }

            let pairingPort = pairing?.port
            let connectPort = connect?.port
            appendLog("WIRELESS: discovered \(serviceSummary(services)).", level: .success)

            if pairing == nil {
                let message = "Found \(host), but the pairing service was not advertised. Open Pair device with pairing code on the phone and click Discover again."
                wirelessDiscoveryMessage = message
                return (host, pairingPort, connectPort)
            }
            if connectPort == nil {
                let message = "Found \(host) and pairing port \(pairingPort ?? 0). The connect service was not advertised; keep the connect port at 5555."
                wirelessDiscoveryMessage = message
                return (host, pairingPort, connectPort)
            }

            wirelessDiscoveryMessage = "Found \(host) — pairing port \(pairingPort ?? 0), connect port \(connectPort ?? 0)."
            return (host, pairingPort, connectPort)
        } catch {
            let message = "Wireless discovery failed. \(Self.friendlyMessage(for: error))"
            wirelessDiscoveryMessage = message
            appendLog("WIRELESS: \(message)", level: .warning)
            return nil
        }
    }

    private func serviceSummary(_ services: [ADBMDNSService]) -> String {
        services.map { "\($0.kind.rawValue) \($0.hostPort)" }.joined(separator: ", ")
    }

    private func isWirelessSerial(_ serial: String) -> Bool {
        serial.contains(":")
            || serial.range(of: "_adb-tls-connect._tcp", options: .caseInsensitive) != nil
    }

    private func isMDNSSerial(_ serial: String) -> Bool {
        serial.range(of: "_adb-tls-connect._tcp", options: .caseInsensitive) != nil
    }

    private func updateWirelessEndpointCache(
        raw: [AndroidDevice],
        normalized: [AndroidDevice]
    ) {
        let mdnsDevices = normalized.filter { isMDNSSerial($0.serial) }
        guard !mdnsDevices.isEmpty else {
            wirelessEndpointCache = [:]
            return
        }

        var cache: [String: WirelessEndpoint] = [:]
        for mdnsDevice in mdnsDevices {
            for rawDevice in raw {
                guard let endpoint = WirelessEndpoint(serial: rawDevice.serial),
                      samePhoneIdentity(rawDevice, mdnsDevice)
                else {
                    continue
                }
                cache[mdnsDevice.serial] = endpoint
                break
            }
        }
        wirelessEndpointCache = cache
    }

    private func samePhoneIdentity(_ lhs: AndroidDevice, _ rhs: AndroidDevice) -> Bool {
        if let lhsModel = normalizedIdentity(lhs.model),
           let rhsModel = normalizedIdentity(rhs.model),
           lhsModel == rhsModel {
            return true
        }
        if let lhsProduct = normalizedIdentity(lhs.product),
           let rhsProduct = normalizedIdentity(rhs.product),
           lhsProduct == rhsProduct {
            return true
        }
        return false
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let collapsed = normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private func rememberWirelessSerial(_ serial: String) {
        guard isWirelessSerial(serial) else { return }
        let changed = storedWirelessSerial != serial
        storedWirelessSerial = serial
        guard !isDemoMode else { return }
        UserDefaults.standard.set(serial, forKey: MMDefaults.wirelessSerial)
        if changed {
            appendLog("WIRELESS: saved serial \(serial).", level: .info)
        }
    }

    private func rememberWirelessEndpoint(_ endpoint: WirelessEndpoint) {
        let changed = storedWirelessEndpoint != endpoint
        storedWirelessEndpoint = endpoint
        guard !isDemoMode else { return }
        if let data = try? JSONEncoder().encode(endpoint) {
            UserDefaults.standard.set(data, forKey: MMDefaults.wirelessEndpoint)
        }
        if changed {
            appendLog("WIRELESS: saved endpoint \(endpoint.serial).", level: .info)
        }
    }

    func pairAndConnect(
        host: String,
        pairingPort: Int,
        code: String,
        connectPort: Int
    ) async throws {
        guard toolchain != nil else {
            throw MotoMirrorError.toolMissing("adb")
        }
        isPairing = true
        defer { isPairing = false }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        appendLog("Pairing with \(trimmedHost):\(pairingPort)…", level: .info)
        do {
            let pairMessage = try await adb.pair(
                host: trimmedHost,
                port: pairingPort,
                code: code
            )
            appendLog(pairMessage, level: .success)
            try? await Task.sleep(nanoseconds: 500_000_000)
            appendLog("Connecting to \(trimmedHost):\(connectPort)…", level: .info)
            let connectMessage = try await adb.connect(host: trimmedHost, port: connectPort)
            appendLog(connectMessage, level: .success)
            if let endpoint = try? WirelessEndpoint(host: trimmedHost, port: connectPort) {
                rememberWirelessEndpoint(endpoint)
                lastWirelessConnectAttempt = Date()
            }
            await refreshDevices()
            let serial = "\(trimmedHost):\(connectPort)"
            if devices.contains(where: { $0.serial == serial }) {
                select(serial)
            }
            errorMessage = nil
        } catch {
            appendLog("Wireless setup failed: \(Self.friendlyMessage(for: error))", level: .error)
            throw error
        }
    }

    // MARK: - Logs

    func appendLog(_ message: String, level: AppLogLevel = .info, source: String = "app") {
        addLog(message, level: level, source: source, date: Date())
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func addLog(_ message: String, level: AppLogLevel, source: String, date: Date) {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let capped = cleaned.count > 700 ? String(cleaned.prefix(700)) + "…" : cleaned
        logs.append(AppLogEntry(date: date, level: level, source: source, message: capped))
        if logs.count > 800 {
            logs.removeFirst(logs.count - 800)
        }
    }

    private func mergeControllerLogs() async {
        let lines = await scrcpy.logs()
        mergeControllerLogs(lines)
    }

    private func mergeControllerLogs(_ lines: [String]) {
        if lines.count < controllerLogCount {
            controllerLogCount = 0
        }
        guard lines.count > controllerLogCount else { return }
        for line in lines.dropFirst(controllerLogCount) {
            let lower = line.lowercased()
            let level: AppLogLevel
            if lower.contains("error") || lower.contains("failed") || lower.contains("could not") {
                level = .error
            } else if lower.contains("warn") {
                level = .warning
            } else {
                level = .info
            }
            addLog(line, level: level, source: "scrcpy", date: Date())
        }
        controllerLogCount = lines.count
    }

    private func seedLogs(for scenario: DemoScenario) {
        let now = Date()
        switch scenario {
        case .connected:
            addLog("adb and scrcpy are ready.", level: .success, source: "app", date: now.addingTimeInterval(-42))
            addLog("Scanning for Android devices…", level: .info, source: "app", date: now.addingTimeInterval(-39))
            addLog("Found Moto G85 over USB.", level: .success, source: "app", date: now.addingTimeInterval(-37))
            addLog("Selected Moto G85 over USB.", level: .info, source: "app", date: now.addingTimeInterval(-36))
            addLog("Battery 72% · Android 15 · 1080 × 2400", level: .info, source: "adb", date: now.addingTimeInterval(-35))
            addLog("Ready to mirror. Connect over USB for the lowest latency.", level: .info, source: "app", date: now.addingTimeInterval(-34))
        case .unauthorized:
            addLog("Scanning for Android devices…", level: .info, source: "app", date: now.addingTimeInterval(-12))
            addLog("Moto G85 is connected but not authorized.", level: .warning, source: "adb", date: now.addingTimeInterval(-10))
            addLog("Unlock the phone and accept the USB debugging prompt.", level: .info, source: "app", date: now.addingTimeInterval(-9))
        case .empty:
            addLog("Scanning for Android devices…", level: .info, source: "app", date: now.addingTimeInterval(-8))
            addLog("No devices found. Waiting for a USB or wireless connection.", level: .info, source: "app", date: now.addingTimeInterval(-7))
        case .setup:
            addLog("adb and scrcpy were not found on this Mac.", level: .warning, source: "app", date: now.addingTimeInterval(-6))
            addLog("Install both tools, then click Check Again.", level: .info, source: "app", date: now.addingTimeInterval(-5))
        }
    }

    // MARK: - File helpers

    private func makeRecordingURL(serial: String) -> URL? {
        let directory = recordingFolderURL
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(
                "MotoMirror-\(Self.fileSafe(serial))-\(Self.fileStamp()).mp4"
            )
        } catch {
            errorMessage = "Could not create the recordings folder at \(directory.path)."
            appendLog("Recording folder error: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private static func fileSafe(_ value: String) -> String {
        let mapped = value.map { character -> String in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return String(character)
            }
            return "-"
        }
        return mapped.joined()
    }

    private static func delayLabel(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "less than a second" }
        return "\(Int(seconds.rounded()))s"
    }

    // MARK: - Formatting

    private static func shortVersion(_ raw: String, name: String) -> String {
        let patterns = [
            #"Version\s+(\d+(?:\.\d+)+)"#,
            #"(\d+\.\d+(?:\.\d+)?)"#
        ]
        for pattern in patterns {
            if let range = raw.range(of: pattern, options: .regularExpression) {
                let match = String(raw[range])
                if let numberRange = match.range(of: #"\d+(?:\.\d+)+"#, options: .regularExpression) {
                    return "\(name) \(match[numberRange])"
                }
            }
        }
        return name
    }

    private static func shorten(_ text: String, limit: Int = 260) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    static func friendlyMessage(for error: Error) -> String {
        if let mirrorError = error as? MotoMirrorError {
            switch mirrorError {
            case .toolMissing(let name):
                return "\(name) was not found. Install it from Setup & Help, then try again."
            case .deviceNotFound:
                return "That phone is no longer connected. Reconnect it over USB or Wi-Fi, then refresh."
            case .deviceUnauthorized:
                return "Your phone has not authorized this Mac. Unlock it and tap Allow on the USB debugging prompt."
            case .invalidInput(let message):
                return message
            case .timeout(let executable):
                return "\(executable) took too long to respond. Check the cable or wireless connection and try again."
            case .parseFailure(let message):
                return "Could not read the phone's response: \(message)"
            case .commandFailed(let executable, _, let stderr):
                let detail = shorten(stderr)
                let lower = detail.lowercased()
                if lower.contains("unauthorized") {
                    return "Your phone has not authorized this Mac. Unlock it and accept the USB debugging prompt."
                }
                if lower.contains("no devices") || lower.contains("device not found") {
                    return "No phone is connected. Reconnect it over USB or Wi-Fi, then refresh."
                }
                if lower.contains("not found") {
                    return "\(executable) could not be found. Open Setup & Help to install the tools."
                }
                if detail.isEmpty {
                    return "\(executable) reported an error. Refresh and try again."
                }
                return "\(executable): \(detail)"
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, !nsError.localizedDescription.isEmpty {
            return nsError.localizedDescription
        }
        return error.localizedDescription
    }

    private func persistOptions() {
        guard !isDemoMode else { return }
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: MMDefaults.options)
    }

    private func persistPreset() {
        guard !isDemoMode else { return }
        UserDefaults.standard.set(preset.rawValue, forKey: MMDefaults.preset)
    }

    private func presetDidChange(from oldValue: MirrorPreset) {
        guard preset != oldValue, !isApplyingPreset else { return }

        if let presetOptions = preset.options {
            isApplyingPreset = true
            options = presetOptions
            isApplyingPreset = false
            persistOptions()
            persistPreset()
            appendLog("Mirror preset: \(preset.title) — \(preset.subtitle).", level: .info)
        } else {
            persistPreset()
        }
    }

    private func optionsDidChange(from oldValue: ScrcpyOptions) {
        guard options != oldValue, !isApplyingPreset else { return }

        persistOptions()
        if preset != .custom {
            preset = .custom
            persistPreset()
            appendLog("Mirror preset switched to Custom.", level: .info)
        }
    }

    private static func loadOptions() -> ScrcpyOptions {
        guard
            let data = UserDefaults.standard.data(forKey: MMDefaults.options),
            let options = try? JSONDecoder().decode(ScrcpyOptions.self, from: data)
        else {
            return .default
        }
        return options
    }

    private static func loadWirelessEndpoint() -> WirelessEndpoint? {
        guard let data = UserDefaults.standard.data(forKey: MMDefaults.wirelessEndpoint) else {
            return nil
        }
        return try? JSONDecoder().decode(WirelessEndpoint.self, from: data)
    }
}

// MARK: - Device display helpers

extension AndroidDevice {
    var mmTransportLabel: String {
        switch transport {
        case .usb: return "USB"
        case .wireless: return "Wi-Fi"
        case .unknown: return "ADB"
        }
    }

    var mmTransportIcon: String {
        switch transport {
        case .usb: return "cable.connector"
        case .wireless: return "wifi"
        case .unknown: return "terminal"
        }
    }

    var mmStateLabel: String {
        switch state {
        case .device: return "Connected"
        case .offline: return "Offline"
        case .unauthorized: return "Needs authorization"
        case .authorizing: return "Authorizing"
        case .connecting: return "Connecting"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Unavailable services

struct UnavailableADBService: ADBServicing {
    let toolName: String
    init(toolName: String = "adb") { self.toolName = toolName }

    private var missing: MotoMirrorError { .toolMissing(toolName) }

    func version() async throws -> String { throw missing }
    func devices() async throws -> [AndroidDevice] { throw missing }
    func details(for serial: String) async throws -> DeviceDetails { throw missing }
    func screenshot(serial: String) async throws -> Data { throw missing }
    func pair(host: String, port: Int, code: String) async throws -> String { throw missing }
    func connect(host: String, port: Int) async throws -> String { throw missing }
    func mdnsServices() async throws -> [ADBMDNSService] { throw missing }
    func disconnect(host: String, port: Int) async throws { throw missing }
    func enableTCPIP(serial: String, port: Int) async throws { throw missing }
    func sendKey(_ key: String, to serial: String) async throws { throw missing }
    func isReady(serial: String) async -> Bool { false }
}

struct UnavailableScrcpyService: ScrcpyControlling {
    let toolName: String
    init(toolName: String = "scrcpy") { self.toolName = toolName }

    func version() async throws -> String { throw MotoMirrorError.toolMissing(toolName) }
    func start(serial: String, options: ScrcpyOptions, recordPath: String?) async throws {
        throw MotoMirrorError.toolMissing(toolName)
    }
    func stop() async {}
    func status() async -> ScrcpyStatus { ScrcpyStatus(state: .idle) }
    func logs() async -> [String] { [] }
}
