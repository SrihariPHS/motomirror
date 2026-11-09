# MotoMirror Verification Report

- Run ID: 20261109-172038
- Started: 2026-11-09T17:20:38+11:00
- Finished: 2026-11-09T17:22:04+11:00
- Mode: live
- Target: any
- Device: emulator-5554 — sdk_gphone64_arm64 (Android 15, SDK 35, unknown)
- Score: 100/100 weighted checks (100.0%)
- Threshold: 99% — PASS (zero failed checks required; live mode also requires zero skipped checks)
- Status counts: 100 passed, 0 failed, 0 skipped

## Categories

| Category | Passed | Failed | Skipped | Total |
| --- | ---: | ---: | ---: | ---: |
| Environment | 10 | 0 | 0 | 10 |
| Build | 12 | 0 | 0 | 12 |
| Unit tests | 12 | 0 | 0 | 12 |
| App/UI | 12 | 0 | 0 | 12 |
| Device basics | 16 | 0 | 0 | 16 |
| Mirroring | 18 | 0 | 0 | 18 |
| Wireless | 8 | 0 | 0 | 8 |
| Docs | 6 | 0 | 0 | 6 |
| Robustness | 6 | 0 | 0 | 6 |

## Failed checks

None.

## Checks

| ID | Category | Status | Title |
| --- | --- | --- | --- |
| E01 | Environment | pass | adb is installed |
| E02 | Environment | pass | adb version runs |
| E03 | Environment | pass | scrcpy is installed |
| E04 | Environment | pass | scrcpy is 5.0.1 |
| E05 | Environment | pass | ffmpeg is installed |
| E06 | Environment | pass | ffmpeg version runs |
| E07 | Environment | pass | ffprobe or ffmpeg fallback available |
| E08 | Environment | pass | Python is 3.9 or newer |
| E09 | Environment | pass | adb server responds |
| E10 | Environment | pass | Repository layout is complete |
| B01 | Build | pass | swift build (debug) succeeds |
| B02 | Build | pass | Debug motomirrorctl exists and is executable |
| B03 | Build | pass | Debug MotoMirror app binary exists |
| B04 | Build | pass | swift build -c release succeeds |
| B05 | Build | pass | Release motomirrorctl exists and is executable |
| B06 | Build | pass | Release MotoMirror app binary exists |
| B07 | Build | pass | MotoMirror.app bundle exists |
| B08 | Build | pass | Info.plist is valid with required keys |
| B09 | Build | pass | App bundle identifier is valid |
| B10 | Build | pass | App version is declared |
| B11 | Build | pass | App icon is declared or bundled |
| B12 | Build | pass | App bundle signature verifies |
| U01 | Unit tests | pass | swift test exits zero |
| U02 | Unit tests | pass | At least 20 tests execute |
| U03 | Unit tests | pass | Zero test failures |
| U04 | Unit tests | pass | All-tests banner reports success |
| U05 | Unit tests | pass | Parser tests are present |
| U06 | Unit tests | pass | scrcpy command tests are present |
| U07 | Unit tests | pass | Validation tests cover hosts, ports, and pairing codes |
| U08 | Unit tests | pass | Process runner tests are present |
| U09 | Unit tests | pass | Controller/session tests are present |
| U10 | Unit tests | pass | At least three test source files exist |
| U11 | Unit tests | pass | Test count is parsed from output |
| U12 | Unit tests | pass | Test run completes inside its timeout |
| A01 | App/UI | pass | App --snapshot exits zero |
| A02 | App/UI | pass | Snapshot has a PNG signature |
| A03 | App/UI | pass | Snapshot is at least 800x600 |
| A04 | App/UI | pass | Snapshot is larger than 20 KB |
| A05 | App/UI | pass | Snapshot is not blank |
| A06 | App/UI | pass | Snapshot has at least 32 sampled colors |
| A07 | App/UI | pass | Demo connected snapshot renders |
| A08 | App/UI | pass | Demo empty snapshot renders |
| A09 | App/UI | pass | Demo unauthorized snapshot renders |
| A10 | App/UI | pass | Demo setup snapshot renders |
| A11 | App/UI | pass | Demo snapshots are visually distinct |
| A12 | App/UI | pass | App executable is a Mach-O binary |
| D01 | Device basics | pass | A usable device is present |
| D02 | Device basics | pass | CLI devices JSON reports the device |
| D03 | Device basics | pass | Device model matches the target |
| D04 | Device basics | pass | Transport matches the target |
| D05 | Device basics | pass | Android version is readable |
| D06 | Device basics | pass | SDK is Android 11 or newer |
| D07 | Device basics | pass | ABI is readable |
| D08 | Device basics | pass | Battery level is readable |
| D09 | Device basics | pass | Battery status, temperature, voltage |
| D10 | Device basics | pass | Storage totals are consistent |
| D11 | Device basics | pass | Screen size and density are readable |
| D12 | Device basics | pass | CLI screenshot writes a PNG |
| D13 | Device basics | pass | Screenshot is at least 800x600 |
| D14 | Device basics | pass | Screenshot is not blank |
| D15 | Device basics | pass | Input keyevent is injected |
| D16 | Device basics | pass | UI hierarchy dump is readable |
| M01 | Mirroring | pass | Headless mirror runs for 8 seconds |
| M02 | Mirroring | pass | Mirror recording file is substantial |
| M03 | Mirroring | pass | Recording contains video frames |
| M04 | Mirroring | pass | Recording video codec is H.264 |
| M05 | Mirroring | pass | Mirror session stays alive for 8 seconds |
| M06 | Mirroring | pass | Recording width matches the device |
| M07 | Mirroring | pass | Recording height matches the device |
| M08 | Mirroring | pass | Recording frame rate is non-zero |
| M09 | Mirroring | pass | Recording includes an audio stream |
| M10 | Mirroring | pass | Session logs contain no fatal errors |
| M11 | Mirroring | pass | Second mirror session starts cleanly |
| M12 | Mirroring | pass | Second recording is valid |
| M13 | Mirroring | pass | Device stays connected after mirroring |
| M14 | Mirroring | pass | No orphan scrcpy processes remain |
| M15 | Mirroring | pass | No-audio mirror session runs |
| M16 | Mirroring | pass | No-audio recording has no audio stream |
| M17 | Mirroring | pass | Max-size and max-fps session runs |
| M18 | Mirroring | pass | Max-size and max-fps limits are applied |
| W01 | Wireless | pass | adb tcpip enables the wireless port |
| W02 | Wireless | pass | Wireless connect lists the device |
| W03 | Wireless | pass | CLI reports wireless transport |
| W04 | Wireless | pass | Wireless screenshot is valid |
| W05 | Wireless | pass | Mirror runs over wireless |
| W06 | Wireless | pass | Wireless recording is valid H.264 |
| W07 | Wireless | pass | Wireless disconnect succeeds |
| W08 | Wireless | pass | Wireless device disappears after disconnect |
| DOC01 | Docs | pass | README.md exists and is substantive |
| DOC02 | Docs | pass | README has a real install/setup section |
| DOC03 | Docs | pass | README documents USB debugging |
| DOC04 | Docs | pass | README documents wireless pairing |
| DOC05 | Docs | pass | README has troubleshooting guidance |
| DOC06 | Docs | pass | Verification docs cover categories and artifacts |
| R01 | Robustness | pass | CLI reports a missing device without crashing |
| R02 | Robustness | pass | CLI doctor --json parses |
| R03 | Robustness | pass | Unknown CLI command exits nonzero |
| R04 | Robustness | pass | wireless pair rejects an invalid pairing code |
| R05 | Robustness | pass | verify.sh is executable and syntactically valid |
| R06 | Robustness | pass | CLI version command reports 1.0.0 |

## Artifacts

- `artifacts/app-demo-connected.png` (567987 bytes, SHA256 `482a83310d20ef8b514abc1f6f16714131a27582ba56d478b02cad8446dadc81`)
- `artifacts/app-demo-empty.png` (559372 bytes, SHA256 `5047e106c24f500fb9f5db34f3b2a43ff947d3853c3ef311e16d680155b73549`)
- `artifacts/app-demo-setup.png` (522406 bytes, SHA256 `e7cb0102ac79f553524223b2a3eef52aa8348c0e15ccf81869bca9e9a244e01b`)
- `artifacts/app-demo-unauthorized.png` (507372 bytes, SHA256 `38c42b144aa63daa689f33fcdca1d9caf9ad418a24dc669670655bde142864f3`)
- `artifacts/app-snapshot.png` (568012 bytes, SHA256 `d2c829cc364a6cfe152ae1dee27f9cc2c4aec033bb1096fc63b5b5f7654a5dc9`)
- `artifacts/mirror.mp4` (2331714 bytes, SHA256 `64ca28ee05af6a859a55342f8a06578840fe62cd9fed8edbacc52371bba75bad`)
- `artifacts/mirror2.mp4` (2660474 bytes, SHA256 `ece7df06b6737ebbf9ec941aaff6169cf0fe8929e62cbc8cb663d08ad984fb46`)
- `artifacts/mirror2_session.log` (1835 bytes, SHA256 `d62a5a0c3876eaeacf0c72395e57e88620cee462b77db33cf1b149946ede9d65`)
- `artifacts/mirror_limits.mp4` (542927 bytes, SHA256 `a295d50354a583e065711bffe856e17233829265d78976669b328e88c2400f2d`)
- `artifacts/mirror_limits_session.log` (1905 bytes, SHA256 `8cb94abf62cafe394bf800a9b66cbac4890c635b9042034d79a8f6b5e9b288f1`)
- `artifacts/mirror_no_audio.mp4` (2453967 bytes, SHA256 `f8be8a6696ea2ee424e2d00e463e46a05b13cbc1f93f16df1754e6c56d5e5c13`)
- `artifacts/mirror_no_audio_session.log` (1798 bytes, SHA256 `831696508cd89ca8824e8d8178711614e99b26cb4d1a39d233e95087b8b34f4e`)
- `artifacts/mirror_session.log` (1828 bytes, SHA256 `6f952e940835b4d852f7a6a7cb22c99b463194991dfe2761e84e2247991d6c4b`)
- `artifacts/screenshot.png` (1375231 bytes, SHA256 `96499e1abe0520bd36f424e2a49db8031e1af02b6e99158f8f70cbbfa58ead18`)
- `artifacts/unit-tests-20261109-172038.log` (23387 bytes, SHA256 `dc002b57f39c3de031ad2ce3ca4804539ded8f0c81682732f6db01564426c8ed`)
- `artifacts/wireless.mp4` (2107799 bytes, SHA256 `857d66ffa968a45c3a72d888c3d619f90a76d6943f56644b99b981ada7776fe6`)
- `artifacts/wireless.png` (1375286 bytes, SHA256 `537b9d6fe7d07997686d04bd6a74f446c1f37951284a756176903ff50081a174`)
- `artifacts/wireless_session.log` (2009 bytes, SHA256 `5ba43b5bd11441c30271d200c1f81f13874c230eddcd796af7672230b1cb145e`)
