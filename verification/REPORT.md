# MotoMirror Verification Report

- Run ID: 20261111-090535
- Started: 2026-11-11T09:05:35+11:00
- Finished: 2026-11-11T09:07:16+11:00
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

- `artifacts/app-demo-connected.png` (558696 bytes, SHA256 `7a7d89d6874e1801fc53bbec1fc97c83d89f50b41bc55e9f5d383529c82c38e4`)
- `artifacts/app-demo-empty.png` (559687 bytes, SHA256 `5e9c2042b348f93ab9b3d3d2040f0264604f855a1ca12dfcfd15ae8457540036`)
- `artifacts/app-demo-setup.png` (522750 bytes, SHA256 `829be09cbcb4e21a970642fdccd76da2a64874379323b324e9c0083c0c0e4c70`)
- `artifacts/app-demo-unauthorized.png` (507715 bytes, SHA256 `54c1ed3a2642bc8308341c30797c06b27d0b289ad43506b0842cdf08d1b3d019`)
- `artifacts/app-snapshot.png` (558510 bytes, SHA256 `4fae9027ea5181e87cde506bc1d32dd7a53a3eb72bb4198d11a78b3f9e0c87d3`)
- `artifacts/mirror.mp4` (2068058 bytes, SHA256 `5d2f63f4093949103221ad3e02610ad41f26f524cec3c426ec3ac1b019dbe3e7`)
- `artifacts/mirror2.mp4` (2263714 bytes, SHA256 `d38cb4dbc8fd194f9cbf8fba8b0a1c088a391194e36d08f8e85030d6a2282025`)
- `artifacts/mirror2_session.log` (1835 bytes, SHA256 `98db03f920075428e10107d5c0a84163bc42cd7b73842909ba40003e7a56150c`)
- `artifacts/mirror_limits.mp4` (414566 bytes, SHA256 `78df39ba74b17c93a6267c964dbc7fdd199f9ca9f9a96c5b5c4f6cf0ade60439`)
- `artifacts/mirror_limits_session.log` (1905 bytes, SHA256 `8ea9933c482d5d37f19b8b2f4491944081de81c846767c3ba2b4908c11ad328e`)
- `artifacts/mirror_no_audio.mp4` (2174017 bytes, SHA256 `50743da8b326a34a4613e0cfc9644e08a807f096b8e4eed9bdb3dd681b5182e9`)
- `artifacts/mirror_no_audio_session.log` (1798 bytes, SHA256 `37305e8d87d97e4b4a5963e6a669797049642cb300f32f4710db009a6c072c79`)
- `artifacts/mirror_session.log` (1828 bytes, SHA256 `4883b15e93019cfa1d4baf6bb7f0ec592a2fd1c5a88b4473fe512e05e47d61fc`)
- `artifacts/screenshot.png` (182388 bytes, SHA256 `43ef9d1940c1676c31f7164eb32790af327e2a882a2901148527c43178a24073`)
- `artifacts/unit-tests-20261111-090535.log` (34202 bytes, SHA256 `1c42312af478b2ca1cca463d050064bb3d870925a2075dea7214356678eaf599`)
- `artifacts/wireless.mp4` (1474411 bytes, SHA256 `5fb9eacec23a5160ebeb08174d5764372c230f42605e3a523b3aaa5224d27c62`)
- `artifacts/wireless.png` (1380666 bytes, SHA256 `b380079aadda71ce2c9daa44db72afe5a20f4128b7125e6f7be1b517f4fa4e1a`)
- `artifacts/wireless_session.log` (2009 bytes, SHA256 `391b2124f7aa6027293fcc55f0157a06a6643f3cdb995644cb2cccb590653a24`)
