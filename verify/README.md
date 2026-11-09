# MotoMirror verification

`verify/verify.py` is the 100-check verification harness for MotoMirror. It is
written for Python 3.9+ and uses only the standard library. `scripts/verify.sh`
is the only supported entry point; it resolves the repository root and forwards
every argument.

```bash
scripts/verify.sh                          # static gate: 58 checks, 42 live checks skipped
scripts/verify.sh --live                   # 100 checks against the connected device
scripts/verify.sh --live --target moto     # final physical Moto G85 gate
scripts/verify.sh --live --target any --wait-for-device 60
```

## Gates

| Gate | Command | What it proves |
| --- | --- | --- |
| Static | `scripts/verify.sh` | Environment, build, unit tests, app snapshot rendering, docs, CLI/robustness. No phone required. |
| Emulator / development | `scripts/verify.sh --live --target any` | Device basics, mirroring, and wireless against any Android 11+ device or emulator. |
| Physical Moto | `scripts/verify.sh --live --target moto` | The final gate: model contains `moto` and `g85`, USB transport, real screenshot, real scrcpy H.264 recording with audio, input injection, UI dump, a second session, and wireless tcpip/connect/mirror/disconnect. |

The target gate must be the Moto G85 on USB. `--target any` deliberately
accepts emulators and other phones; it is not final evidence for the product
goal.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--live` | off | Execute the 42 device checks. Without it they are reported as `skip` with evidence `requires --live`. |
| `--target {moto,any}` | `any` | `moto` requires a Moto G85 model string and USB transport. |
| `--wait-for-device SECONDS` | `0` | Poll `adb devices` for a usable device before the device checks. |
| `--threshold N` | `99` | Minimum passing percentage. At 100 checks, 99 permits one failed check; use `--threshold 100` to require zero failures. Static mode scores only the 58 executed checks. |
| `--json-out PATH` | `verification/report.json` | Machine-readable report. |
| `--report PATH` | `verification/REPORT.md` | Human-readable report with evidence for every failed check. |
| `--keep-artifacts` | off | Keep previous files in `artifacts/` instead of clearing the directory at the start of the run. |
| `--verbose` | off | Print each check as it finishes. |

Exit code is `0` only when the weighted score meets the threshold **and zero
checks failed**. In live mode zero checks may also be skipped. Any failed check
is printed with its evidence, and the same evidence is written to
`verification/REPORT.md`.

## The 100 checks

| Category | Checks | Live? | Coverage |
| --- | ---: | --- | --- |
| Environment | 10 | no | adb, scrcpy 5.0.1, ffmpeg/ffprobe, Python, adb server, repository layout. |
| Build | 12 | no | Debug and release `swift build`, CLI/app binaries, `.app` bundle, Info.plist, bundle id, version, icon, code signature. |
| Unit tests | 12 | no | `swift test` exit status, at least 20 executed tests, zero failures, parser/command/validation/runner/controller coverage. Validation must include the named hostname, port, and pairing-code rejection tests. |
| App/UI | 12 | no | `MotoMirror --snapshot` produces a non-blank PNG at least 800x600 and larger than 20 KB; demo snapshots for connected, empty, unauthorized, and error states are distinct; executable is Mach-O. |
| Device basics | 16 | yes | Device presence, CLI devices JSON, model, transport, Android/SDK/ABI, battery, storage, screen, PNG screenshot and non-blank pixels, keyevent injection, UI hierarchy dump. |
| Mirroring | 18 | yes | Headless 8-second scrcpy session, MP4 recording, H.264 video, decoded frame count, dimensions matching the device, frame rate, audio stream, fatal log scan, second session, no orphan processes, `--no-audio`, `--max-size`, `--max-fps`. The harness injects swipes during recording so a static screen still emits frames; it proves the session stayed alive for the requested wall-clock time instead of trusting container duration. |
| Wireless | 8 | yes | `adb tcpip`, wireless connect, transport reported by the CLI, wireless screenshot, wireless mirror and recording, disconnect, and removal from `adb devices`. Emulators switch adbd to **5555** and connect to `127.0.0.1:5555` (guest Wi-Fi IPs are not reachable from the host); physical phones use their Wi-Fi IP on **5559**. |
| Docs | 6 | no | README has a real install/setup heading plus command (`make setup`), USB debugging, wireless pairing, troubleshooting, and verification headings; this file covers categories, threshold, and artifacts. |
| Robustness | 6 | no | Missing-device CLI error, `doctor --json` parsing, invalid command exit code, invalid pairing-code rejection, executable `verify.sh`, and `motomirrorctl version`. |

### Wireless pairing limitation

A successful `adb pair` needs the one-time six-digit code shown on the phone,
which the harness cannot obtain. W01-W08 therefore verify the post-pairing
wireless path only: `adb tcpip`, connect, transport reporting, screenshot,
mirror/recording, disconnect, and removal from `adb devices`. R04 verifies that
`motomirrorctl wireless pair` rejects an invalid pairing code locally with a
clear error instead of claiming a fake success. Successful live pairing is not
claimed by this suite.

Every check carries weight 1. A check object in the reports looks like:

```json
{
  "id": "M04",
  "category": "Mirroring",
  "title": "Recording video codec is H.264",
  "status": "pass",
  "evidence": "$ .../motomirrorctl mirror ...\nexit=0\n...",
  "weight": 1
}
```

Reports are written once, after every check and artifact exists. `runId`,
`startedAt`, and `finishedAt` identify the run. Each artifact entry includes
`bytes` and `sha256`; the Markdown report prints the same hash so the evidence
on disk can be matched to the report.

`status` is `pass`, `fail`, or `skip`. Exceptions never produce a pass: the
harness catches per-check errors and records the exception text as evidence.
If a live check cannot run because the phone lacks a capability, it is marked
`fail`, not `skip`.

## Reading `verification/report.json`

- `mode`: `static` or `live`.
- `target`: `moto` or `any`.
- `device`: serial, model, manufacturer, Android version, SDK, transport.
- `score`: passed/failed/skipped counts, executed weight, total checks,
  percentage, threshold, and `gatePassed`.
- `checks`: all 100 check objects in category order, each with evidence.
- `artifacts`: relative paths and byte sizes of files produced by the run.

In static mode `score.percent` is computed only over executed checks and
`score.skipped` is 42. In live mode all 100 checks execute or fail; nothing is
skipped.

## Artifacts

Generated files live in `artifacts/` at the repository root:

- `app-snapshot.png` and `app-demo-{connected,empty,unauthorized,error}.png`
- `screenshot.png` and `wireless.png`
- `mirror.mp4`, `mirror2.mp4`, `mirror_limits.mp4`, `mirror_no_audio.mp4`,
  `wireless.mp4`
- `unit-tests-<runId>.log` with the full `swift test` output, so a test failure
  names the failing case and cannot be confused with an earlier run
- `*_session.log` mirror session logs

Reports live in `verification/` (`REPORT.md` and `report.json` by default).
The harness clears `artifacts/` at the start unless `--keep-artifacts` is
passed, so a report never points at stale media from an earlier run.

## Threshold semantics

The score is weighted passes divided by executed weight. `--threshold` is the
minimum percentage, but the gate is stricter: **zero failed checks are
allowed**. A live run must also execute all 100 checks, so zero skips are
allowed. A 99/100 run with one failed check prints `FAIL`, even at
`--threshold 99`. In static mode the 42 live checks are skipped and excluded
from the denominator, so `scripts/verify.sh` prints `static score X/58, live
score pending`; it cannot certify the physical product goal by itself.

The MotoMirror definition of done is `scripts/verify.sh --live --target moto`
with 100/100 passing checks, zero failed checks, and an evidence line for every
check in `verification/REPORT.md`.
