# MotoMirror requirements manifest

Goal: a native macOS app that connects a Motorola Moto G85 (or any Android 11+ phone) over USB or wireless ADB and mirrors it with scrcpy, with a verified score of at least 99/100 on the project's live verification suite.

Bar: scrcpy 5.0.1 as the transport reference, plus the setup and status UX of a native Mac utility. The critic compares actual app behavior and screenshots against scrcpy's own CLI behavior.

Definition of done: `./scripts/verify.sh --live` produces at least 99/100 with zero failed checks against the target phone, and every check has an evidence line in `verification/REPORT.md`.

| ID | Requirement | Acceptance criteria | Status |
| --- | --- | --- | --- |
| R1 | Project scaffold | Swift package builds a macOS app, a core library, a CLI, and a test target | pending |
| R2 | Tool discovery | Finds adb, scrcpy, ffmpeg in PATH, Homebrew, Android SDK, and app resources; reports missing tools | pending |
| R3 | Device discovery | Parses `adb devices -l`, states, models, USB/wireless transport; polls without hanging | pending |
| R4 | Device details | Reads battery, storage, screen size, Android version, SDK, ABI | pending |
| R5 | Mirror launch | Starts scrcpy with serial, bitrate, size, FPS, audio, recording, stay-awake and window options | pending |
| R6 | Session lifecycle | Start, stop, restart, exit code, logs, and stale-process cleanup | pending |
| R7 | Screenshot | Captures a PNG through adb and reveals it in Finder | pending |
| R8 | Recording | Records an MP4 through scrcpy and reveals it in Finder | pending |
| R9 | Wireless pairing | `adb pair`, `adb connect`, `adb tcpip`, validation, and clear errors | pending |
| R10 | Auto reconnect | Detects a dropped device and restarts mirroring when it returns | pending |
| R11 | Setup guidance | In-app USB debugging steps, dependency install action, unauthorized-device guidance | pending |
| R12 | App UI | Native SwiftUI device list, detail panel, options, logs, empty/error/unauthorized states | pending |
| R13 | Demo mode | Renders every UI state with sample data for screenshots and verification | pending |
| R14 | CLI | `motomirrorctl doctor`, `devices`, `info`, `screenshot`, `mirror`, `wireless` | pending |
| R15 | Packaging | Builds a signed `.app` with icon, Info.plist, and install script | pending |
| R16 | Unit tests | Parsers, command builder, validation, process runner, and controller logic tested | pending |
| R17 | Live verification | 100 weighted checks produce a JSON and Markdown report with evidence | pending |
| R18 | Real mirror proof | Live scrcpy recording with valid H.264 video and audio; screenshot proof from the phone | pending |
| R19 | Physical Moto check | Moto G85 model, USB transport, input injection, and live mirror all pass | pending |
| R20 | Docs | README covers install, USB debugging, wireless pairing, troubleshooting, and verification | pending |
