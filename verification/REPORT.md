# MotoMirror Verification Report

- Run ID: 20261111-064202
- Started: 2026-11-11T06:42:02+11:00
- Finished: 2026-11-11T06:43:40+11:00
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

- `artifacts/app-demo-connected.png` (558637 bytes, SHA256 `8a97108357f876c58ab3b799aa694a31681c0d4f20bcab2023bf4c43b43e3304`)
- `artifacts/app-demo-empty.png` (559687 bytes, SHA256 `5e9c2042b348f93ab9b3d3d2040f0264604f855a1ca12dfcfd15ae8457540036`)
- `artifacts/app-demo-setup.png` (522750 bytes, SHA256 `829be09cbcb4e21a970642fdccd76da2a64874379323b324e9c0083c0c0e4c70`)
- `artifacts/app-demo-unauthorized.png` (507715 bytes, SHA256 `54c1ed3a2642bc8308341c30797c06b27d0b289ad43506b0842cdf08d1b3d019`)
- `artifacts/app-snapshot.png` (558594 bytes, SHA256 `badb86bf63e9d4165a28a7dbdd806f453dfff44c9818b0f4048c0a55c960b938`)
- `artifacts/mirror.mp4` (874186 bytes, SHA256 `9bd34ab638fe08a06128058f5a9c4055fe52f9aa0c986c25000ed68ab1283e49`)
- `artifacts/mirror2.mp4` (1224210 bytes, SHA256 `7aab1e1085bca5a83f7fba72d79cd30b6038acc22ea71a943ab787b794486331`)
- `artifacts/mirror2_session.log` (1833 bytes, SHA256 `63637457482c4c109743ac9b437e251403a0c0e9ddd2c8fcd1f1485e30fec360`)
- `artifacts/mirror_limits.mp4` (389262 bytes, SHA256 `e1381ffe88c154bfafd671805b2ff5c72cea633efc8abeb49e830b0a081e89c3`)
- `artifacts/mirror_limits_session.log` (1903 bytes, SHA256 `6a9df27dcc53a8c28b0410b14ebaf883e022260d8ac320d7237f05580e6139e5`)
- `artifacts/mirror_no_audio.mp4` (654725 bytes, SHA256 `129426b6e5b0f46fb3e50be1751ff0c3b4068315ded7a90dec7948d9b68c5119`)
- `artifacts/mirror_no_audio_session.log` (1794 bytes, SHA256 `4b85ae7210a7cddaebc321b9aeb4828a831a0ccf8e740cf96aec886e3dcf2f84`)
- `artifacts/mirror_session.log` (1824 bytes, SHA256 `ed28e34597942d85ecf4339a7b9810b291777d6614347cf09cd11459d8fe07f9`)
- `artifacts/screenshot.png` (181292 bytes, SHA256 `5bd1700515a156f68f0f661aeade9dc23eb3ba59c2dd478593bbcba66663f597`)
- `artifacts/unit-tests-20261111-064202.log` (34202 bytes, SHA256 `de77bb3512fe49ca818c66be1ae53a3421ecf336d73f0c3e6163eaffaff6be16`)
- `artifacts/wireless.mp4` (1182485 bytes, SHA256 `175a74907adb173a514882b85409d424831e47a645b14c266d9ffd37a3c4f609`)
- `artifacts/wireless.png` (1380357 bytes, SHA256 `5ab463c20306f4c2fbcf5c3f2a242ed5539844dd4349b6d2e35fc8585638675c`)
- `artifacts/wireless_session.log` (2007 bytes, SHA256 `748ccdb0013cd811880979e3a9764a5838f23f0aef303dca9f95367f751aabf5`)
