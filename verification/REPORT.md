# MotoMirror Verification Report

- Run ID: 20261109-202617
- Started: 2026-11-09T20:26:17+11:00
- Finished: 2026-11-09T20:27:57+11:00
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

- `artifacts/app-demo-connected.png` (558267 bytes, SHA256 `7815d006fe5cec6479f0d7834dd2f747ac3411402ce259ee815e1421092e51bb`)
- `artifacts/app-demo-empty.png` (559372 bytes, SHA256 `5047e106c24f500fb9f5db34f3b2a43ff947d3853c3ef311e16d680155b73549`)
- `artifacts/app-demo-setup.png` (522406 bytes, SHA256 `e7cb0102ac79f553524223b2a3eef52aa8348c0e15ccf81869bca9e9a244e01b`)
- `artifacts/app-demo-unauthorized.png` (507372 bytes, SHA256 `38c42b144aa63daa689f33fcdca1d9caf9ad418a24dc669670655bde142864f3`)
- `artifacts/app-snapshot.png` (558057 bytes, SHA256 `493b2f6effcfccaa6845cefa4da653e66a066e55dc1fdc54d84df9725ace2656`)
- `artifacts/mirror.mp4` (1188156 bytes, SHA256 `868a93eec3d9d422ec26ad60ce7d4734f5b1e473e8729d36402569abb621231f`)
- `artifacts/mirror2.mp4` (1620151 bytes, SHA256 `c524f10cfd909b1e2956c6a72fa1e6d4078a34a6894e91bf571688b629c08b20`)
- `artifacts/mirror2_session.log` (1835 bytes, SHA256 `167c669f09db2a41e0ce47dca9d8ff7aedc0d415f8e91602b5aa20d147f39084`)
- `artifacts/mirror_limits.mp4` (295092 bytes, SHA256 `140e3ed443b31a1c8d0597cdd31bb160c7a897590a538c611107726bbfe5ef78`)
- `artifacts/mirror_limits_session.log` (1905 bytes, SHA256 `07947bc8ea4ee70ac741a274d2d6b1ceb219e76b99c42c768bf0a32a3fb63594`)
- `artifacts/mirror_no_audio.mp4` (961727 bytes, SHA256 `9c6dbe6f641a4489a218e6ef00a90a07fc0d652845c4bcf51b7e05cccbf53da2`)
- `artifacts/mirror_no_audio_session.log` (1798 bytes, SHA256 `4bac431321e62a12a3a76864f332149db137becbf9b8ac7f9e125a251cfddfe9`)
- `artifacts/mirror_session.log` (1826 bytes, SHA256 `06d7df3fe259784032b2b1276130e08fcb7f187adc0b94e8e8603ec802df0d0c`)
- `artifacts/screenshot.png` (171233 bytes, SHA256 `3d4762d7cdbc0142f61bbb686f665f6dd1cb68b9c97814ace57ac9f617376ef3`)
- `artifacts/unit-tests-20261109-202617.log` (33113 bytes, SHA256 `882fcb5c68327b64422832ba72028611e9430816f7431e3bdad046809617c2bb`)
- `artifacts/wireless.mp4` (945403 bytes, SHA256 `f00497828f387ecb7b366d14e52ce291658f68d1352af5b65512b149863d7350`)
- `artifacts/wireless.png` (1379081 bytes, SHA256 `52e64c27a70dd8e2fe84d0349a7b1c3125d2d46365c45490843914f56c4bf2f3`)
- `artifacts/wireless_session.log` (2009 bytes, SHA256 `ef160e0ec197ed061a5bc09f4da350b9c3b9f1402dd189c3dca893a9bce6854f`)
