# Progress

## 2026-11-09

- Recon: Xcode 27.2, Swift 6.4.2, ffmpeg present. adb and scrcpy were missing; installed scrcpy 5.0.1 and Android platform-tools 37.0.2 with Homebrew.
- No Android device is currently attached over USB. The live Moto G85 gate will run when the phone is connected.
- Scaffolded the Swift package, core domain types, service protocols, binary locator, scrcpy command builder, and process runner.
- Next: parallel workers build the ADB layer, scrcpy controller, CLI, SwiftUI app, and packaging/verification harness.

## 2026-11-09 final integration

- Static verification: 58/58 checks, 100%.
- Unit tests: 100 tests, 0 failures. Five consecutive clean runs after the one-off flake.
- Live verification on Android 15 emulator: 100/100, 0 failed, 0 skipped.
- Live mirror: H.264 1080x2400, 130 frames, Opus audio, 7.3s recording.
- Wireless: connect, screenshot, mirror, and disconnect over 127.0.0.1:5555.
- App auto-mirror: scrcpy child process and window "sdk gphone64 arm64 — MotoMirror" observed, then clean quit.
- Auto-reconnect live check: app PID 68536, first scrcpy PID 68555, killed it, second scrcpy PID 68595 appeared with the same parent.
- App bundle built, ad-hoc signed, and installed at ~/Applications/MotoMirror.app.
- Physical Moto G85 gate: not run. The phone is not connected or nearby. This is the only open item.

- Final locked gate run `20261109-172038`: 100/100, 0 failed, 0 skipped, 102 unit tests, Opus audio, 18/18 artifact hashes match disk.
- Critic fixes: zero-failure gate, real R01/R06/U07/DOC02 checks, no screen-size fallback, D10 arithmetic, waited-serial caching, W01 already-in-TCP proof, 10-attempt reconnect budget, SIGTERM cleanup.
- Physical target check `--target moto` was run against the emulator to prove it rejects a non-Moto: 58/100, D01-D16/M/W all failed because the emulator is not a Moto. The 100/100 emulator report was preserved.

Next: connect the Moto G85 with USB debugging enabled and the RSA prompt allowed, then run `make verify-live`. The physical gate adds model contains moto/g85 and USB transport checks. Use `./scripts/verify-loop.sh 0 600` for a continuous gate.
- Wireless discovery: added `ADBMDNSService`/`ADBMDNSParser`, `WirelessEndpoint`, `ADBClient.mdnsServices`, app Discover button, and `motomirrorctl wireless discover --json`. 9 parser/endpoint tests pass. The emulator advertises no mDNS services, so the Discover button is build-verified but not live-exercised.
- Wireless reconnect: app mirrored over 127.0.0.1:5555, endpoint disconnected, app re-ran adb connect and started a new scrcpy child on the wireless serial. Persisted endpoint JSON observed.
- Final gate run 20261109-180730: 100/100, 0 failed, 0 skipped, 111 unit tests, 18/18 artifact hashes match. M14 false positive fixed to use process executable names.
- Physical Moto pair-code flow still needs the phone. The app must be tested with the actual six-digit code from the Moto's Wireless debugging dialog.

## 2026-11-09 presets + batched details

- Added `MirrorPreset` core presets: `quality` (1920/12/60/audio), `balanced` (1440/8/60/audio), `batterySaver` (720/4/30/no-audio/screen-off), plus `custom` with no fixed options. `ScrcpyOptions.default` is now `MirrorPreset.balanced.options!`, so the default never asks for native max-size 0.
- Added `DeviceListNormalizer.normalize(_:)`: when `adb` reports both the stable mDNS serial (`_adb-tls-connect._tcp`) and an `IP:port` alias for the same model/product, the mDNS entry wins and the IP alias is dropped; USB entries and different models are untouched, and winning entries keep input order.
- `ADBClient.details(for:)` now runs one marked `adb shell` command (`__PROPS__`, `__BATTERY__`, `__STORAGE__`, `__SCREEN__`) instead of four sequential round trips and feeds the existing parsers. A failed battery section leaves the other sections intact. Live Moto G85: 4 calls -> 1, measured 0.41-0.47s -> 0.28-0.34s per details refresh.
- Live `motomirrorctl info` against the Moto G85 returned model moto g85 5G, Android 16, battery 60% charging, storage, and 1080x2400 @ 400 dpi through the batched path.
- Files: `Sources/MotoMirrorCore/MirrorPreset.swift`, `DeviceListNormalizer.swift`, `Models.swift` (default only), `ADBClient.swift`; `Tests/MotoMirrorCoreTests/PresetTests.swift`, `DeviceListNormalizerTests.swift`, `ADBClientTests.swift`, `ScrcpyCommandTests.swift` (default assertion).
- `swift test`: 127 tests, 0 failures. Next: wire preset selection into app/CLI (out of scope here).

## 2026-11-09 Tailscale peer discovery

- Added read-only `TailscaleDiscovery`: locates the installed CLI (app bundle, Homebrew, `/usr/local`, then `BinaryLocator`), parses `tailscale status --json` `Peer` entries with `JSONSerialization`, filters/sorts Android peers (online first, then case-insensitive host name), and validates `100.64.0.0/10` addresses.
- `status(using:runner:)` runs `tailscale status --json` with a 15s timeout and requires success. Nothing installs, starts, or configures Tailscale.
- Tests cover online/offline Android, macOS, IPv6-only, missing IP, malformed peers, invalid JSON, missing `Peer`, DNS trailing-dot stripping, CIDR bounds, and a fake CLI proving the `status --json` invocation.
- Files: `Sources/MotoMirrorCore/TailscaleDiscovery.swift`, `Tests/MotoMirrorCoreTests/TailscaleDiscoveryTests.swift`.
- `swift test --filter TailscaleDiscoveryTests`: 11 tests, 0 failures. Full `swift test`: 143 tests, 0 failures.
- Performance: real Moto G85 benchmark shows old 720/20M/90/audio ~600 mA vs Battery Saver 720/4M/30/no-audio/screen-off ~434 mA, about 28% lower. Native resolution triggered a Moto encoder error; explicit 720/1080/1440/1920 sizes are clean. Presets default to Balanced.
- App integration: `--preset battery-saver` produced `--max-size=720 --video-bit-rate=4M --max-fps=30 --no-audio --turn-screen-off`; `--preset balanced` produced `--max-size=1440 --video-bit-rate=8M --max-fps=60` with audio.
- Tailscale: read-only `TailscaleDiscovery` and `motomirrorctl tailscale peers` are implemented and tested. The Mac lists 4 Android peers, all offline; no Moto tailnet node, so Tailscale connectivity to the phone is documented but not live-proven.
- Final gate run 20261109-202617: 100/100, 0 failed, 0 skipped, 143 tests, 18/18 artifact hashes match.
- Agent control: added DeviceActions, UI hierarchy parsing, app launch/stop, UI find/tap/text/key/swipe, files push/pull, shell, screen, volume, logcat, wait-for, agent tools/call, and a 27-tool MCP stdio server.
- USB-only mode: `--usb` and `MOTOMIRROR_TRANSPORT=usb` require a cable and fail clearly without one; app has a USB-only toggle.
- Agent suite: 21/21 live checks on the emulator, including MCP initialize/tools/list/tools/call and a real UI typing test. Moto G85 untouched.
- Full gate run 20261111-062810: 100/100, 0 failed, 0 skipped, 148 unit tests, 18/18 artifact hashes.
- Agent suite expanded to 24/24: added apps stop, volume set, screen sleep/wake, and a retry-hardened Settings navigation path. Three consecutive runs passed.
- Final gate run 20261111-064229: 100/100, 0 failed, 0 skipped, 148 tests, 18/18 hashes.
