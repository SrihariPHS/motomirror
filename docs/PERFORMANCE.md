# Performance

Measurements from a Moto G85 on Android 16 over wireless ADB. They are
directional, not lab-grade. Use them to choose a preset, not to predict exact
battery life.

## Method

- Phone: Moto G85, Android 16.
- Transport: wireless ADB. scrcpy 5.0.1.
- Duration: 12 seconds per run, 2 repeats per profile.
- Current: sampled once per second from
  `/sys/class/power_supply/battery/current_now`.
- FPS: parsed from scrcpy `--print-fps`.
- Network: `wlan0` byte counters.
- Screen state: screen-on runs opened Settings and looped a scroll gesture to
  create motion. Screen-off runs kept the display off and the screen static.
- The values below are averages of the two run averages. The range is the
  lowest and highest run average.

Screen-off FPS is low because the display was static. scrcpy only sends frames
when the content changes. Do not compare that number to interactive mirroring.

## Measured

| Profile | Settings | Average current | Run range | Mean FPS |
| --- | --- | ---: | ---: | ---: |
| Old current profile | 720 px, 20 Mbps, 90 fps, audio, screen on | 600 mA | 519–681 mA | 55–60 |
| Battery Saver | 720 px, 4 Mbps, 30 fps, no audio, screen off | 434 mA | 383–485 mA | 12–17 |
| Native fallback | Native size, 4 Mbps, 30 fps, no audio, screen off | 408 mA | 301–516 mA | 12–17 |
| 720 H.265 experiment | 720 px, 4 Mbps, 30 fps, H.265, no audio, screen off | 460 mA | 298–622 mA | 5–10 |

Battery Saver averaged about **28% less current** than the old profile:
434 mA against 600 mA. The ranges are wide. Treat the saving as directional.

The native-size row is not a preset. Native resolution triggered an encoder
error and a fallback. Explicit 720, 1080, 1440, and 1920 px sizes produced
clean sessions. Every preset pins a size so it does not ask for native.

H.265 was not clearly better. It produced lower and more erratic FPS, so it is
not the default codec. Quality and Balanced were not benchmarked directly.
Only the 720 px profile was measured. Explicit 1080, 1440, and 1920 px sessions
were clean but not timed for this table.

## What changed

- **Three presets.** Quality is 1920 px, 12 Mbps, 60 fps, audio, screen on.
  Balanced is 1440 px, 8 Mbps, 60 fps, audio, screen on. Battery Saver is
  720 px, 4 Mbps, 30 fps, no audio, screen off.
- **Balanced is the default.** `ScrcpyOptions.default` maps to Balanced.
- **One-time migration.** The first launch of this version replaces old stored
  options with Balanced once. Later choices are left alone.
- **Batched details.** Device details now use one `adb shell` round trip for
  `getprop`, `dumpsys battery`, `df -k /data`, and `wm size` / `wm density`.
  Before, that took four round trips.
- **Stable mDNS serial.** Wireless ADB can report the same phone twice: once as
  an `IP:port` alias and once as an mDNS serial such as
  `adb-...._adb-tls-connect._tcp`. MotoMirror keeps the reachable alias and
  prefers the mDNS serial when both are equally usable. That serial survives
  wireless port changes and prevents duplicate rows and avoidable restarts.
- **Explicit size caps.** Native resolution hit the encoder error and fallback.
  Presets use 1920, 1440, or 720 explicitly. H.265 is not the default.

## Rerun the benchmark

Connect the Moto G85 over wireless ADB and confirm that it is visible:

```bash
adb devices -l
```

Run the benchmark:

```bash
python3 verification/bench_profiles.py --duration 12 --repeats 2 --out verification/perf.json
```

The script selects a `moto g85` device automatically and exits if none is
attached. Pass `--serial` to pick a specific one. It uses `adb` and `scrcpy`
from `PATH`, wakes the phone, runs each profile with
`--time-limit=12 --print-fps`, and writes JSON to the output path.
The full profile list and flags are at the top of
[`verification/bench_profiles.py`](../verification/bench_profiles.py).

The script edits phone state: it wakes the phone, opens Settings for screen-on
runs, and turns the screen off for screen-off runs. Do not run it unattended.

## Caveats

- 12-second runs and 2 repeats. Short samples, not a battery lab.
- Wireless only. USB charging and cable power change the result.
- Screen-off profiles were static. Their 12–17 FPS does not predict interactive
  mirroring.
- Battery current is reported by the phone and is coarse.
- The native-size run used a fallback path. Do not compare it to explicit sizes.
- H.265 has too little data to recommend. It is excluded from the presets.
- Temperature, background apps, signal strength, and Android version can move
  the numbers.
