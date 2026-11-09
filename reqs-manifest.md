# MotoMirror requirements manifest

Goal: a native macOS app that connects a Motorola Moto G85 (or any Android 11+ phone) over USB or wireless ADB and mirrors it with scrcpy, with a verified score of at least 99/100 on the project's live verification suite.

Bar: scrcpy 5.0.1 as the transport reference, plus the setup and status UX of a native Mac utility. The critic compares actual app behavior and screenshots against scrcpy's own CLI behavior.

Definition of done: `./scripts/verify.sh --live` produces at least 99/100 with zero failed checks against the target phone, and every check has an evidence line in `verification/REPORT.md`.

| ID | Requirement | Acceptance criteria | Status |
| --- | --- | --- | --- |
| R1 | Project scaffold | Swift package builds a macOS app, a core library, a CLI, and a test target | done |
| R2 | Tool discovery | Finds adb, scrcpy, ffmpeg in PATH, Homebrew, Android SDK, and app resources; reports missing tools | done |
| R3 | Device discovery | Parses `adb devices -l`, states, models, USB/wireless transport; polls without hanging | done |
| R4 | Device details | Reads battery, storage, screen size, Android version, SDK, ABI | done |
| R5 | Mirror launch | Starts scrcpy with serial, bitrate, size, FPS, audio, recording, stay-awake and window options | done |
| R6 | Session lifecycle | Start, stop, restart, exit code, logs, and stale-process cleanup | done |
| R7 | Screenshot | Captures a PNG through adb and reveals it in Finder | done |
| R8 | Recording | Records an MP4 through scrcpy and reveals it in Finder | done |
| R9 | Wireless pairing | `adb pair`, `adb connect`, `adb tcpip`, validation, and clear errors | done (pair code unit-tested; physical pair pending) |
| R10 | Auto reconnect | Detects a dropped device and restarts mirroring when it returns | done (live wireless endpoint reconnect verified) |
| R11 | Setup guidance | In-app USB debugging steps, dependency install action, unauthorized-device guidance | done |
| R12 | App UI | Native SwiftUI device list, detail panel, options, logs, empty/error/unauthorized states | done |
| R13 | Demo mode | Renders every UI state with sample data for screenshots and verification | done |
| R14 | CLI | `motomirrorctl doctor`, `devices`, `info`, `screenshot`, `mirror`, `wireless` | done |
| R15 | Packaging | Builds a signed `.app` with icon, Info.plist, and install script | done |
| R16 | Unit tests | Parsers, command builder, validation, process runner, and controller logic tested | done |
| R17 | Live verification | 100 weighted checks produce a JSON and Markdown report with evidence | done |
| R18 | Real mirror proof | Live scrcpy recording with valid H.264 video and audio; screenshot proof from the phone | done (Android 15 emulator; Moto pending) |
| R19 | Physical Moto check | Moto G85 model, USB transport, input injection, and live mirror all pass | pending (phone not connected) |
| R20 | Docs | README covers install, USB debugging, wireless pairing, troubleshooting, and verification | done |

## 2026-11-09 real-phone profile and speed update

| ID | Requirement | Acceptance criteria | Status |
| --- | --- | --- | --- |
| R21 | Presets and faster details | `MirrorPreset` exposes quality/balanced/batterySaver options and a nil-options custom case; `ScrcpyOptions.default` is balanced; `DeviceListNormalizer` collapses mDNS + IP aliases for one phone; `ADBClient.details` uses one marked adb shell round trip instead of four and keeps partial results when a section fails; unit tests cover each behavior | done (app preset picker and migration verified; 143 tests) |
| R22 | Tailscale peer discovery | `TailscaleDiscovery` locates the CLI, parses `tailscale status --json` `Peer` entries, filters/sorts Android peers, validates `100.64.0.0/10` addresses, and runs `status --json` with a 15s timeout; read-only and unit tested | done (`swift test` 143/143; 11 Tailscale tests) |
