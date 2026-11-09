# MotoMirror Verification Report

- Run ID: 20261109-212157
- Started: 2026-11-09T21:21:57+11:00
- Finished: 2026-11-09T21:23:36+11:00
- Mode: live
- Target: any
- Device: 127.0.0.1:5555 — sdk_gphone64_arm64 (Android 15, SDK 35, wireless)
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
| D04 | Device basics | pass | Transport and model match the target |
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
| W01 | Wireless | pass | Wireless transport is established |
| W02 | Wireless | pass | Wireless target is already connected |
| W03 | Wireless | pass | CLI reports the wireless device |
| W04 | Wireless | pass | Wireless screenshot is valid |
| W05 | Wireless | pass | Mirror runs over wireless |
| W06 | Wireless | pass | Wireless recording is valid H.264 |
| W07 | Wireless | pass | Wireless disconnect is clean |
| W08 | Wireless | pass | Wireless device remains usable or recovers |
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

- `artifacts/app-demo-connected.png` (557944 bytes, SHA256 `44bd89e322b0787c1d3a4c4bdeed2800097e1cdcdb359f41dddcd095da166c5f`)
- `artifacts/app-demo-empty.png` (559372 bytes, SHA256 `5047e106c24f500fb9f5db34f3b2a43ff947d3853c3ef311e16d680155b73549`)
- `artifacts/app-demo-setup.png` (522406 bytes, SHA256 `e7cb0102ac79f553524223b2a3eef52aa8348c0e15ccf81869bca9e9a244e01b`)
- `artifacts/app-demo-unauthorized.png` (507372 bytes, SHA256 `38c42b144aa63daa689f33fcdca1d9caf9ad418a24dc669670655bde142864f3`)
- `artifacts/app-snapshot.png` (557907 bytes, SHA256 `bb3c1ae042fd4d6999cfa713fd827d7887319a7f9f376e28b6b716ded7decf54`)
- `artifacts/mirror.mp4` (2373421 bytes, SHA256 `b2a68209b581c437a91aa7ecca1fbe79313030809651f6f64fc89da56d0d142f`)
- `artifacts/mirror2.mp4` (2622375 bytes, SHA256 `741fb33310120741f86e360e6cc54a5787de59b2531ad6697bd638a53b8fba8f`)
- `artifacts/mirror2_session.log` (1835 bytes, SHA256 `549be992294f8199b23c6b7c1feecebf41cf83a4a763008021108a6854d5acaa`)
- `artifacts/mirror_limits.mp4` (526611 bytes, SHA256 `5cdb6e56e32a615f9a420e0d35e8ff7551c6e60039fe1fc8767077926998cd33`)
- `artifacts/mirror_limits_session.log` (1905 bytes, SHA256 `fbfb06c869d7f8e6cd7fd6626470a57ed005138239466439e2474976578f6356`)
- `artifacts/mirror_no_audio.mp4` (2449965 bytes, SHA256 `276679b205a4f4597c6bc81e8ada7bd8552e24179b6365e12d45ad87282a7d85`)
- `artifacts/mirror_no_audio_session.log` (1798 bytes, SHA256 `125dc7896ac76c701ad3c23fca65b4aa1336c0e7221f84bb724df6ff76a3c57a`)
- `artifacts/mirror_session.log` (1828 bytes, SHA256 `71430298ebe10676f1deea470f6d6a9e40f01fab8560d76e12ebabe8fa737afe`)
- `artifacts/screenshot.png` (1379537 bytes, SHA256 `bcefefb3bc11ff49c2c84b59dbde8a7da7ec9807706393eab34ab8882750d81b`)
- `artifacts/unit-tests-20261109-212157.log` (33073 bytes, SHA256 `380561b5ddeeb02bccb1e35b47ed7bcc2cc59d13c20dc097f8f79b4da7b8af48`)
- `artifacts/wireless.mp4` (1790215 bytes, SHA256 `2b9035d57496db00ccef227856724fa7386f218907740b6251fbcb6013821d85`)
- `artifacts/wireless.png` (1379708 bytes, SHA256 `eee3216fcd38ae7f0bd4e0245c7c4bac9ccdc22d1b003e1a3e0afd42b16f8add`)
- `artifacts/wireless_session.log` (2009 bytes, SHA256 `35bb4f3764d18ac28427e7fcc94bc8c3167ae5d6beccc2b3b97fc4118bf3d906`)
