#!/usr/bin/env python3
"""Measure scrcpy profiles on a real Android phone over wireless ADB.

The phone must already be connected and visible in `adb devices -l`.
Battery current comes from /sys/class/power_supply/battery/current_now.
Network bytes come from wlan0 tx_bytes. FPS comes from scrcpy --print-fps.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import threading
import time
from pathlib import Path

ADB = "adb"
SCRCPY = "scrcpy"
DURATION = 12
REPEATS = 2

PROFILES = [
    ("current_720_20M_90_audio", ["--max-size=720", "--video-bit-rate=20M", "--max-fps=90", "--stay-awake"], True, False),
    ("native_8M_60_audio", ["--video-bit-rate=8M", "--max-fps=60", "--stay-awake"], True, False),
    ("native_6M_60_audio", ["--video-bit-rate=6M", "--max-fps=60", "--stay-awake"], True, False),
    ("native_6M_60_noaudio", ["--video-bit-rate=6M", "--max-fps=60", "--stay-awake", "--no-audio"], False, False),
    ("native_4M_30_audio", ["--video-bit-rate=4M", "--max-fps=30", "--stay-awake"], True, False),
    ("native_4M_30_noaudio_screenoff", ["--video-bit-rate=4M", "--max-fps=30", "--stay-awake", "--no-audio", "--turn-screen-off"], False, True),
    ("720_4M_30_noaudio_screenoff", ["--max-size=720", "--video-bit-rate=4M", "--max-fps=30", "--stay-awake", "--no-audio", "--turn-screen-off"], False, True),
    ("native_4M_30_h265_noaudio_screenoff", ["--video-bit-rate=4M", "--max-fps=30", "--stay-awake", "--no-audio", "--turn-screen-off", "--video-codec=h265"], False, True),
    ("720_4M_30_h265_noaudio_screenoff", ["--max-size=720", "--video-bit-rate=4M", "--max-fps=30", "--stay-awake", "--no-audio", "--turn-screen-off", "--video-codec=h265"], False, True),
]


def run(args, timeout=30, check=False):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=check)


def phone_serial():
    out = run([ADB, "devices", "-l"]).stdout
    candidates = []
    for line in out.splitlines():
        if "\tdevice" not in line:
            continue
        if "moto_g85" not in line.lower() and "moto g85" not in line.lower():
            continue
        serial = line.split()[0]
        candidates.append(serial)
    if not candidates:
        raise SystemExit("No connected Moto G85 found in adb devices -l")
    # The mDNS serial survives wireless debugging port changes.
    for serial in candidates:
        if "_adb-tls-connect._tcp" in serial:
            return serial
    return candidates[0]


class Phone:
    def __init__(self, serial):
        self.serial = serial

    def shell(self, command, timeout=30):
        return run([ADB, "-s", self.serial, "shell", command], timeout=timeout)

    def read_int(self, path):
        out = self.shell(f"cat {path} 2>/dev/null").stdout.strip()
        try:
            return int(out)
        except ValueError:
            return None

    def wake(self):
        self.shell("input keyevent KEYCODE_WAKEUP")
        self.shell("wm dismiss-keyguard")

    def home(self):
        self.shell("input keyevent KEYCODE_HOME")

    def net_tx(self):
        # Android 16 denies /sys/class/net/wlan0/statistics/tx_bytes to shell.
        output = self.shell("cat /proc/net/dev").stdout
        for line in output.splitlines():
            if line.strip().startswith("wlan0:"):
                parts = line.replace(":", " ").split()
                if len(parts) > 9:
                    try:
                        return int(parts[9])
                    except ValueError:
                        return None
        return None

    def battery(self):
        return {
            "current_uA": self.read_int("/sys/class/power_supply/battery/current_now"),
            "charge_uAh": self.read_int("/sys/class/power_supply/battery/charge_counter"),
            "tx_bytes": self.net_tx(),
            "temperature": self.read_int("/sys/class/power_supply/battery/temp"),
        }


class Motion:
    def __init__(self, phone, enabled):
        self.phone = phone
        self.enabled = enabled
        self.stop = threading.Event()
        self.thread = None

    def __enter__(self):
        if not self.enabled:
            return self
        self.phone.shell("am start -a android.settings.SETTINGS")
        time.sleep(1)

        def loop():
            direction = True
            while not self.stop.is_set():
                if direction:
                    self.phone.shell("input swipe 540 1800 540 700 220")
                else:
                    self.phone.shell("input swipe 540 700 540 1800 220")
                direction = not direction
                self.stop.wait(0.30)

        self.thread = threading.Thread(target=loop, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stop.set()
        if self.thread:
            self.thread.join(timeout=3)
        self.phone.wake()
        self.phone.home()


def mac_cpu(pid):
    out = run(["ps", "-p", str(pid), "-o", "%cpu="]).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return None


def parse_fps(text):
    values = [float(v) for v in re.findall(r"([0-9]+(?:\.[0-9]+)?) fps", text)]
    return {
        "samples": values,
        "mean": round(statistics.mean(values), 2) if values else None,
        "max": max(values) if values else None,
    }


def measure(phone, name, args, audio, screen_off):
    before = phone.battery()
    phone.wake()
    if screen_off:
        phone.home()

    command = [
        SCRCPY,
        f"--serial={phone.serial}",
        f"--window-title=Perf-{name}",
        f"--time-limit={DURATION}",
        "--print-fps",
    ] + args

    samples = []
    cpu_samples = []
    started = time.time()
    with Motion(phone, enabled=not screen_off):
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        while process.poll() is None:
            time.sleep(1.0)
            sample = phone.battery()
            sample["t"] = round(time.time() - started, 2)
            samples.append(sample)
            cpu = mac_cpu(process.pid)
            if cpu is not None:
                cpu_samples.append(cpu)
        output = process.stdout.read() if process.stdout else ""
        exit_code = process.wait()

    after = phone.battery()
    if screen_off:
        phone.wake()

    currents = [abs(s["current_uA"]) for s in samples if s.get("current_uA") is not None]
    tx = [s["tx_bytes"] for s in samples if s.get("tx_bytes") is not None]
    tx_delta = (tx[-1] - tx[0]) if len(tx) >= 2 else None
    seconds = max(0.001, samples[-1]["t"] - samples[0]["t"]) if len(samples) >= 2 else DURATION
    mbps = (tx_delta * 8 / seconds / 1_000_000) if tx_delta is not None else None
    fps = parse_fps(output)
    charge_delta = None
    if before.get("charge_uAh") is not None and after.get("charge_uAh") is not None:
        charge_delta = after["charge_uAh"] - before["charge_uAh"]

    return {
        "profile": name,
        "exit_code": exit_code,
        "duration_s": round(time.time() - started, 2),
        "avg_current_mA": round(statistics.mean(currents) / 1000, 1) if currents else None,
        "min_current_mA": round(min(currents) / 1000, 1) if currents else None,
        "max_current_mA": round(max(currents) / 1000, 1) if currents else None,
        "charge_delta_uAh": charge_delta,
        "tx_mbps": round(mbps, 2) if mbps is not None else None,
        "mac_cpu_percent_avg": round(statistics.mean(cpu_samples), 1) if cpu_samples else None,
        "fps": fps,
        "temperature_before": before.get("temperature"),
        "temperature_after": after.get("temperature"),
        "battery_level": {"before": before.get("charge_uAh"), "after": after.get("charge_uAh")},
        "args": args,
        "audio": audio,
        "screen_off": screen_off,
        "log_tail": "\n".join(output.splitlines()[-25:]),
    }


def main():
    global DURATION
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", default=None)
    parser.add_argument("--duration", type=int, default=DURATION)
    parser.add_argument("--repeats", type=int, default=REPEATS)
    parser.add_argument("--out", default="verification/perf.json")
    args = parser.parse_args()

    DURATION = args.duration
    serial = args.serial or phone_serial()
    phone = Phone(serial)
    print(f"serial={serial} duration={DURATION}s repeats={args.repeats}")

    results = []
    for name, profile_args, audio, screen_off in PROFILES:
        runs = []
        for repeat in range(args.repeats):
            print(f"  {name} run {repeat + 1}/{args.repeats}", flush=True)
            try:
                runs.append(measure(phone, name, profile_args, audio, screen_off))
            except Exception as exc:  # noqa: BLE001
                runs.append({"profile": name, "error": repr(exc), "args": profile_args})
        results.append({
            "profile": name,
            "args": profile_args,
            "audio": audio,
            "screen_off": screen_off,
            "runs": runs,
        })

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({"serial": serial, "duration": DURATION, "results": results}, indent=2))
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
