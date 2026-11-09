#!/usr/bin/env python3
"""MotoMirror 100-check verification harness.

Static mode (default) runs 58 checks that do not need a phone and marks the
42 device checks as skipped. Live mode (--live) executes all 100 checks against
the connected Android device, including a real scrcpy recording with ffprobe
validation.

Python 3 standard library only. Every subprocess has a timeout. No check can
pass because of an exception: exceptions are recorded as failures with the
exception text as evidence.
"""

import argparse
import hashlib
import json
import os
import plistlib
import re
import shlex
import shutil
import struct
import subprocess
import threading
import sys
import time
import traceback
import zlib
from collections import Counter
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

CATEGORY_COUNTS = {
    "Environment": 10,
    "Build": 12,
    "Unit tests": 12,
    "App/UI": 12,
    "Device basics": 16,
    "Mirroring": 18,
    "Wireless": 8,
    "Docs": 6,
    "Robustness": 6,
}

LIVE_CHECK_COUNT = 16 + 18 + 8


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def is_mdns_serial(serial):
    return "_adb-tls-connect._tcp" in (serial or "").lower()


def truncate(text, limit=1800):
    text = str(text)
    if len(text) <= limit:
        return text
    head = limit // 2
    tail = limit - head
    return text[:head] + "\n...[truncated]...\n" + text[-tail:]


def resolve_path(raw):
    path = Path(raw)
    if not path.is_absolute():
        path = REPO / path
    return path


def parse_fraction(value):
    if value is None:
        return None
    value = str(value)
    if "/" in value:
        numerator, denominator = value.split("/", 1)
        try:
            denominator = float(denominator)
            if denominator == 0:
                return None
            return float(numerator) / denominator
        except ValueError:
            return None
    try:
        return float(value)
    except ValueError:
        return None


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def which_tool(name, override_key):
    override = os.environ.get(override_key)
    if override:
        candidate = Path(os.path.expanduser(override))
        if candidate.is_file() and os.access(str(candidate), os.X_OK):
            return str(candidate)
    directories = os.environ.get("PATH", "").split(os.pathsep)
    directories.extend(
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            str(Path.home() / ".local" / "bin"),
            str(Path.home() / "Library" / "Android" / "sdk" / "platform-tools"),
        ]
    )
    seen = set()
    for directory in directories:
        if not directory or directory in seen:
            continue
        seen.add(directory)
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(str(candidate), os.X_OK):
            return str(candidate)
    return None


class Result:
    __slots__ = ("cmd", "code", "stdout", "stderr", "seconds", "timed_out", "error")

    def __init__(self, cmd, code, stdout="", stderr="", seconds=0.0,
                 timed_out=False, error=None):
        self.cmd = [str(part) for part in cmd]
        self.code = code
        self.stdout = stdout or ""
        self.stderr = stderr or ""
        self.seconds = seconds
        self.timed_out = timed_out
        self.error = error

    @property
    def ok(self):
        return self.code == 0 and not self.timed_out and self.error is None

    @property
    def combined(self):
        text = self.stdout
        if self.stderr:
            if text and not text.endswith("\n"):
                text += "\n"
            text += self.stderr
        return text

    def evidence(self, limit=1800):
        command = shlex.join(self.cmd)
        parts = ["$ " + command, "exit={}".format(self.code)]
        output = self.combined.strip()
        if output:
            parts.append(output)
        if self.timed_out:
            parts.append("[timed out after {:.1f}s]".format(self.seconds))
        if self.error:
            parts.append("[error: {}]".format(self.error))
        return truncate("\n".join(parts), limit)


def png_header(path):
    """Parse the PNG signature and IHDR chunk without decoding pixels."""
    try:
        data = Path(path).read_bytes()
    except OSError as exc:
        raise ValueError("could not read PNG: {}".format(exc))
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise ValueError("missing PNG signature")
    position = 8
    header = None
    while position + 8 <= len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        chunk_type = data[position + 4:position + 8]
        chunk = data[position + 8:position + 8 + length]
        if len(chunk) != length:
            raise ValueError("truncated PNG chunk {}".format(chunk_type))
        position += 12 + length
        if chunk_type == b"IHDR":
            if length != 13:
                raise ValueError("malformed IHDR")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", chunk
            )
            header = {
                "width": width,
                "height": height,
                "bitDepth": bit_depth,
                "colorType": color_type,
                "interlace": interlace,
                "bytes": len(data),
            }
        elif chunk_type == b"IEND":
            break
    if header is None:
        raise ValueError("PNG has no IHDR chunk")
    return header


def png_stats(path):
    """Decode an 8-bit PNG and return dimensions plus blankness statistics.

    Unsupported PNG variants still return header data with blankness set to
    None; callers must treat that as "not verified", never as a pass.
    """
    header = png_header(path)
    header.update({"uniqueColors": None, "channelRange": None, "nonBlank": None})
    if header["bitDepth"] != 8 or header["interlace"] != 0:
        return header
    channels_by_type = {0: 1, 2: 3, 4: 2, 6: 4}
    channels = channels_by_type.get(header["colorType"])
    if channels is None:
        return header

    data = Path(path).read_bytes()
    position = 8
    idat = bytearray()
    while position + 8 <= len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        chunk_type = data[position + 4:position + 8]
        chunk = data[position + 8:position + 8 + length]
        position += 12 + length
        if chunk_type == b"IDAT":
            idat.extend(chunk)
        elif chunk_type == b"IEND":
            break
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        raise ValueError("invalid PNG image data: {}".format(exc))

    width = header["width"]
    height = header["height"]
    stride = width * channels
    if len(raw) < height * (stride + 1):
        raise ValueError("PNG image data is shorter than expected")

    previous = bytearray(stride)
    offset = 0
    colors = set()
    color_limit = 4096
    minimum = 255
    maximum = 0
    total = 0
    total_squared = 0
    samples = 0
    step_x = max(1, width // 160)
    step_y = max(1, height // 160)

    for y in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        if filter_type == 0:
            pass
        elif filter_type == 1:
            for index in range(channels, stride):
                line[index] = (line[index] + line[index - channels]) & 0xFF
        elif filter_type == 2:
            for index in range(stride):
                line[index] = (line[index] + previous[index]) & 0xFF
        elif filter_type == 3:
            for index in range(stride):
                left = line[index - channels] if index >= channels else 0
                line[index] = (line[index] + ((left + previous[index]) >> 1)) & 0xFF
        elif filter_type == 4:
            for index in range(stride):
                left = line[index - channels] if index >= channels else 0
                above = previous[index]
                upper_left = previous[index - channels] if index >= channels else 0
                estimate = left + above - upper_left
                distance_left = abs(estimate - left)
                distance_above = abs(estimate - above)
                distance_upper_left = abs(estimate - upper_left)
                if distance_left <= distance_above and distance_left <= distance_upper_left:
                    predictor = left
                elif distance_above <= distance_upper_left:
                    predictor = above
                else:
                    predictor = upper_left
                line[index] = (line[index] + predictor) & 0xFF
        else:
            raise ValueError("unsupported PNG filter type {}".format(filter_type))

        if y % step_y == 0:
            for x in range(0, width, step_x):
                index = x * channels
                if channels >= 3:
                    red, green, blue = line[index], line[index + 1], line[index + 2]
                else:
                    red = green = blue = line[index]
                if len(colors) < color_limit:
                    colors.add((red, green, blue))
                value = (red + green + blue) // 3
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                total += value
                total_squared += value * value
                samples += 1
        previous = line

    mean = total / samples if samples else 0
    variance = (total_squared / samples) - (mean * mean) if samples else 0
    header["uniqueColors"] = len(colors)
    header["channelRange"] = maximum - minimum
    header["variance"] = round(variance, 2)
    header["nonBlank"] = bool(header["uniqueColors"] > 32
                              or header["channelRange"] > 20
                              or variance > 25)
    return header


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------


class Harness:
    def __init__(self, args):
        self.args = args
        self.artifacts = REPO / "artifacts"
        self.verification = REPO / "verification"
        self.report_path = resolve_path(args.report)
        self.json_path = resolve_path(args.json_out)
        self.tools = {
            "adb": which_tool("adb", "MOTOMIRROR_ADB"),
            "scrcpy": which_tool("scrcpy", "MOTOMIRROR_SCRCPY"),
            "ffmpeg": which_tool("ffmpeg", "MOTOMIRROR_FFMPEG"),
            "ffprobe": which_tool("ffprobe", "MOTOMIRROR_FFPROBE"),
            "swift": shutil.which("swift") or "/usr/bin/swift",
            "python3": sys.executable,
        }
        self.checks = []
        self.results = {}
        self.ctx = {}
        self._bin_paths = {}
        self._app_bundle = False
        self._app_exe = None
        self._snapshot_base = None
        self._demo_snapshots = {}
        self._probe_cache = {}
        self._unit_run = None
        self._mirror_main = None
        self._mirror_second = None
        self._mirror_no_audio = None
        self._mirror_limits = None
        self._wireless_mirror = None
        self._wireless_host_cache = None
        self.run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.started_at = datetime.now().astimezone().isoformat(timespec="seconds")
        self.start_time = time.time()
        self.env = dict(os.environ)
        self.prepare_directories()
        self.tools_override_environment()

    # -- setup ---------------------------------------------------------

    def prepare_directories(self):
        self.artifacts.mkdir(parents=True, exist_ok=True)
        self.verification.mkdir(parents=True, exist_ok=True)
        self.report_path.parent.mkdir(parents=True, exist_ok=True)
        self.json_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.args.keep_artifacts:
            for child in list(self.artifacts.iterdir()):
                try:
                    if child.is_dir() and not child.is_symlink():
                        shutil.rmtree(child)
                    else:
                        child.unlink()
                except OSError:
                    pass

    def tools_override_environment(self):
        overrides = {
            "MOTOMIRROR_ADB": "adb",
            "MOTOMIRROR_SCRCPY": "scrcpy",
            "MOTOMIRROR_FFMPEG": "ffmpeg",
        }
        for variable, tool in overrides.items():
            if os.environ.get(variable) and self.tools.get(tool):
                self.env[variable] = self.tools[tool]

    def add(self, check_id, category, title, live, function):
        self.checks.append(
            {
                "id": check_id,
                "category": category,
                "title": title,
                "live": live,
                "weight": 1,
                "function": function,
            }
        )

    # -- process helpers ----------------------------------------------

    def run(self, command, timeout=60, cwd=None, env=None):
        command = [str(part) for part in command]
        started = time.time()
        try:
            completed = subprocess.run(
                command,
                cwd=str(cwd or REPO),
                capture_output=True,
                text=True,
                timeout=timeout,
                env=env,
            )
            return Result(
                command,
                completed.returncode,
                completed.stdout,
                completed.stderr,
                time.time() - started,
            )
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout or ""
            stderr = exc.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", "replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", "replace")
            return Result(command, -9, stdout, stderr, time.time() - started, timed_out=True)
        except FileNotFoundError as exc:
            return Result(command, 127, "", str(exc), time.time() - started, error=str(exc))
        except OSError as exc:
            return Result(command, 126, "", str(exc), time.time() - started, error=str(exc))

    def binary_paths(self, configuration):
        if configuration in self._bin_paths:
            return self._bin_paths[configuration]
        command = [self.tools["swift"], "build", "--show-bin-path"]
        if configuration == "release":
            command.extend(["-c", "release"])
        result = self.run(command, timeout=120)
        if result.ok and result.stdout.strip():
            path = Path(result.stdout.strip().splitlines()[-1])
        else:
            path = REPO / ".build" / ("release" if configuration == "release" else "debug")
        self._bin_paths[configuration] = path
        return path

    def cli_binary(self):
        if self.ctx.get("cli"):
            return self.ctx["cli"]
        candidates = []
        for configuration in ("debug", "release"):
            candidates.append(self.binary_paths(configuration) / "motomirrorctl")
        candidates.extend(
            [
                REPO / ".build" / "debug" / "motomirrorctl",
                REPO / ".build" / "release" / "motomirrorctl",
            ]
        )
        located = shutil.which("motomirrorctl")
        if located:
            candidates.append(Path(located))
        for candidate in candidates:
            if candidate.is_file() and os.access(str(candidate), os.X_OK):
                self.ctx["cli"] = candidate
                return candidate
        raise RuntimeError(
            "motomirrorctl binary is missing; run 'swift build --product motomirrorctl' first"
        )

    def run_cli(self, arguments, timeout=60):
        return self.run([self.cli_binary()] + list(arguments), timeout=timeout)

    def cli_json(self, arguments, timeout=60):
        result = self.run_cli(arguments, timeout=timeout)
        if not result.ok:
            raise RuntimeError(
                "motomirrorctl {} failed: {}".format(" ".join(arguments), result.evidence(900))
            )
        try:
            return json.loads(result.stdout), result
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                "motomirrorctl {} did not print JSON ({}): {}".format(
                    " ".join(arguments), exc, truncate(result.stdout, 600)
                )
            )

    # -- app discovery --------------------------------------------------

    def find_app_bundle(self):
        if self._app_bundle is not False:
            return self._app_bundle
        candidates = [
            REPO / "build" / "MotoMirror.app",
            REPO / "dist" / "MotoMirror.app",
            REPO / "MotoMirror.app",
            REPO / "output" / "MotoMirror.app",
            REPO / "packaging" / "MotoMirror.app",
            REPO / ".build" / "MotoMirror.app",
            REPO / ".build" / "release" / "MotoMirror.app",
        ]
        for candidate in candidates:
            if candidate.is_dir() and (candidate / "Contents" / "Info.plist").is_file():
                self._app_bundle = candidate
                return candidate
        skip = {".git", ".build", ".swiftpm", "node_modules", "artifacts", "verification"}
        for root, directories, _files in os.walk(REPO):
            root_path = Path(root)
            try:
                depth = len(root_path.relative_to(REPO).parts)
            except ValueError:
                depth = 0
            if depth >= 3:
                directories[:] = []
            directories[:] = [name for name in directories if name not in skip]
            for name in list(directories):
                if name.endswith(".app"):
                    candidate = root_path / name
                    if (candidate / "Contents" / "Info.plist").is_file():
                        self._app_bundle = candidate
                        return candidate
        self._app_bundle = None
        return None

    def app_plist(self):
        bundle = self.find_app_bundle()
        if bundle is None:
            raise RuntimeError("MotoMirror.app bundle not found; packaging has not produced it yet")
        try:
            with open(bundle / "Contents" / "Info.plist", "rb") as handle:
                return bundle, plistlib.load(handle)
        except (OSError, plistlib.InvalidFileException) as exc:
            raise RuntimeError("cannot read Info.plist: {}".format(exc))

    def app_executable(self):
        if self._app_exe:
            return self._app_exe
        bundle = self.find_app_bundle()
        if bundle is not None:
            plist = self.app_plist()[1]
            executable_name = plist.get("CFBundleExecutable") or bundle.stem
            candidate = bundle / "Contents" / "MacOS" / executable_name
            if candidate.is_file():
                self._app_exe = candidate
                return candidate
        for candidate in (
            self.binary_paths("debug") / "MotoMirror",
            self.binary_paths("release") / "MotoMirror",
        ):
            if candidate.is_file() and os.access(str(candidate), os.X_OK):
                self._app_exe = candidate
                return candidate
        raise RuntimeError("MotoMirror app executable not found")

    def take_snapshot(self, path, demo_state=None):
        executable = self.app_executable()
        if demo_state is None:
            forms = [
                (["--snapshot", str(path)], None),
                (["--snapshot={}".format(path)], None),
            ]
        else:
            forms = [
                (["--snapshot", str(path), "--snapshot-state", demo_state], None),
                (["--snapshot", str(path), "--snapshot-state={}".format(demo_state)], None),
                (["--snapshot", str(path), "--demo", demo_state], None),
                (["--snapshot", str(path), "--demo={}".format(demo_state)], None),
                (["--snapshot", str(path), "--state", demo_state], None),
                (
                    ["--snapshot", str(path)],
                    {**os.environ, "MOTOMIRROR_DEMO_STATE": demo_state},
                ),
            ]
        last = None
        for form, env in forms:
            last = self.run([executable] + form, timeout=45, env=env)
            if last.timed_out:
                return last
            if last.ok and path.is_file() and path.stat().st_size > 0:
                return last
        # Snapshot rendering writes from the app process. On a busy Mac the
        # file can appear just after the process exits, so retry once before
        # calling the state a failure.
        time.sleep(1.5)
        if path.is_file() and path.stat().st_size > 0:
            return last
        form, env = forms[0]
        retry = self.run([executable] + form, timeout=45, env=env)
        return retry if retry.ok else last

    def base_snapshot(self):
        if self._snapshot_base is None:
            path = self.artifacts / "app-snapshot.png"
            result = self.take_snapshot(path)
            self._snapshot_base = (result, path)
        return self._snapshot_base

    def demo_snapshot(self, state):
        if state in self._demo_snapshots:
            return self._demo_snapshots[state]
        path = self.artifacts / "app-demo-{}.png".format(state)
        result = self.take_snapshot(path, demo_state=state)
        self._demo_snapshots[state] = (result, path)
        return self._demo_snapshots[state]

    # -- device helpers -------------------------------------------------

    def adb_devices(self):
        if not self.tools["adb"]:
            raise RuntimeError("adb is not installed")
        result = self.run([self.tools["adb"], "devices", "-l"], timeout=25)
        devices = []
        for line in result.stdout.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("List of devices") or stripped.startswith("*"):
                continue
            parts = stripped.split()
            if len(parts) < 2:
                continue
            serial, state = parts[0], parts[1]
            model = None
            transport = "unknown"
            for part in parts[2:]:
                if part.startswith("model:"):
                    model = part.split(":", 1)[1]
                elif part.startswith("usb:"):
                    transport = "usb"
            if transport == "unknown" and ":" in serial and not serial.startswith("emulator-"):
                transport = "wireless"
            elif transport == "unknown" and is_mdns_serial(serial):
                transport = "wireless"
            devices.append(
                {"serial": serial, "state": state, "model": model, "transport": transport}
            )
        return result, devices

    def select_device(self, wait_seconds=0):
        deadline = time.time() + max(0, int(wait_seconds))
        result = None
        devices = []
        while True:
            result, devices = self.adb_devices()
            usable = [device for device in devices if device["state"] == "device"]
            if self.args.target == "moto":
                usable = [
                    device
                    for device in usable
                    if "moto" in (device.get("model") or "").lower().replace("_", " ")
                ]
            if usable:
                # Prefer USB, then a primary (non-endpoint) serial, then an
                # emulator serial. A leftover 127.0.0.1:5555 endpoint must not
                # become the waited device when emulator-5554 is available.
                usable.sort(
                    key=lambda device: (
                        0 if device["transport"] == "usb" else 1,
                        0 if ":" not in device["serial"] else 1,
                        0 if device["serial"].startswith("emulator-") else 1,
                    )
                )
                return usable[0], devices, result
            if time.time() >= deadline:
                return None, devices, result
            time.sleep(min(2.0, max(0.2, deadline - time.time())))

    def set_device(self, device):
        self.ctx["serial"] = device["serial"]
        self.ctx["device"] = device

    def require_serial(self):
        # D01 records the serial it waited for. Every later check must use that
        # same device instead of silently selecting another one.
        waited = self.ctx.get("waited_serial")
        if waited:
            _result, devices = self.adb_devices()
            wanted = next(
                (d for d in devices if d["serial"] == waited and d["state"] == "device"),
                None,
            )
            if wanted is not None:
                return waited
            # A wireless phone can change its IP:port alias or lose one of its
            # two aliases while the same physical device stays reachable.
            cached_model = (self.ctx.get("device") or {}).get("model")
            fallback = [
                d for d in devices
                if d["state"] == "device"
                and cached_model
                and (d.get("model") or "").lower().replace("_", " ")
                == cached_model.lower().replace("_", " ")
            ]
            if fallback:
                fallback.sort(key=lambda d: (0 if is_mdns_serial(d["serial"]) else 1,
                                             0 if d["transport"] == "wireless" else 1))
                self.set_device(fallback[0])
                self.ctx["waited_serial"] = fallback[0]["serial"]
                return fallback[0]["serial"]
        if self.ctx.get("serial"):
            return self.ctx["serial"]
        device, _devices, result = self.select_device(0)
        if device is None:
            raise RuntimeError(
                "no usable device connected; adb devices output:\n{}".format(
                    result.evidence(800) if result else "adb unavailable"
                )
            )
        self.set_device(device)
        return device["serial"]

    def details(self):
        if self.ctx.get("details"):
            return self.ctx["details"]
        serial = self.require_serial()
        payload, _result = self.cli_json(["info", "--serial", serial, "--json"], timeout=60)
        if not isinstance(payload, dict):
            raise RuntimeError("info output was not a JSON object")
        self.ctx["details"] = payload
        return payload

    def screenshot_file(self):
        serial = self.require_serial()
        path = self.artifacts / "screenshot.png"
        result = self.run_cli(
            ["screenshot", "--serial", serial, "--out", str(path)], timeout=90
        )
        if not result.ok:
            raise RuntimeError("screenshot failed: {}".format(result.evidence(900)))
        return result, path

    def probe_media(self, path):
        path = Path(path)
        key = str(path)
        if key in self._probe_cache:
            return self._probe_cache[key]
        probe = {"ok": False, "duration": None, "video": None, "audio": False,
                 "source": None, "raw": ""}
        if not path.is_file():
            probe["raw"] = "file does not exist: {}".format(path)
            self._probe_cache[key] = probe
            return probe

        if self.tools.get("ffprobe"):
            result = self.run(
                [
                    self.tools["ffprobe"],
                    "-v", "error",
                    "-count_frames",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    str(path),
                ],
                timeout=45,
            )
            if result.ok:
                try:
                    data = json.loads(result.stdout)
                    streams = data.get("streams") or []
                    video_stream = next(
                        (stream for stream in streams if stream.get("codec_type") == "video"),
                        None,
                    )
                    video = None
                    if video_stream:
                        frames_raw = (
                            video_stream.get("nb_read_frames")
                            or video_stream.get("nb_frames")
                        )
                        try:
                            frames = int(frames_raw)
                        except (TypeError, ValueError):
                            frames = None
                        video = {
                            "codec": video_stream.get("codec_name"),
                            "width": int(video_stream.get("width") or 0),
                            "height": int(video_stream.get("height") or 0),
                            "fps": parse_fraction(
                                video_stream.get("avg_frame_rate")
                                or video_stream.get("r_frame_rate")
                            ),
                            "frames": frames,
                        }
                    duration = None
                    try:
                        duration = float((data.get("format") or {}).get("duration"))
                    except (TypeError, ValueError):
                        if video_stream:
                            try:
                                duration = float(video_stream.get("duration"))
                            except (TypeError, ValueError):
                                duration = None
                    probe.update(
                        {
                            "ok": True,
                            "duration": duration,
                            "video": video,
                            "audio": any(
                                stream.get("codec_type") == "audio" for stream in streams
                            ),
                            "source": "ffprobe",
                            "raw": truncate(result.stdout, 1200),
                        }
                    )
                    self._probe_cache[key] = probe
                    return probe
                except (json.JSONDecodeError, ValueError, TypeError) as exc:
                    probe["raw"] = "ffprobe JSON error: {}".format(exc)
            else:
                probe["raw"] = result.evidence(800)

        if self.tools.get("ffmpeg"):
            result = self.run(
                [self.tools["ffmpeg"], "-hide_banner", "-i", str(path)], timeout=45
            )
            text = result.stderr or result.stdout
            duration_match = re.search(
                r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", text
            )
            duration = None
            if duration_match:
                hours, minutes, seconds = duration_match.groups()
                duration = int(hours) * 3600 + int(minutes) * 60 + float(seconds)
            video = None
            for line in text.splitlines():
                if "Video:" not in line:
                    continue
                codec_match = re.search(r"Video:\s*([A-Za-z0-9_]+)", line)
                size_match = re.search(r"(\d{2,5})x(\d{2,5})", line)
                fps_match = re.search(r"(\d+(?:\.\d+)?)\s*fps", line)
                if codec_match:
                    video = {
                        "codec": codec_match.group(1),
                        "width": int(size_match.group(1)) if size_match else 0,
                        "height": int(size_match.group(2)) if size_match else 0,
                        "fps": float(fps_match.group(1)) if fps_match else None,
                        "frames": None,
                    }
                    break
            if video is not None:
                count_result = self.run(
                    [
                        self.tools["ffmpeg"], "-hide_banner", "-i", str(path),
                        "-map", "0:v:0", "-f", "null", "-",
                    ],
                    timeout=90,
                )
                counts = re.findall(r"frame=\s*(\d+)", count_result.stderr)
                if counts:
                    video["frames"] = max(int(value) for value in counts)
            probe.update(
                {
                    "ok": video is not None or duration is not None,
                    "duration": duration,
                    "video": video,
                    "audio": "Audio:" in text,
                    "source": "ffmpeg",
                    "raw": truncate(text, 1200),
                }
            )
            self._probe_cache[key] = probe
            return probe

        probe["raw"] = "ffprobe and ffmpeg are both missing"
        self._probe_cache[key] = probe
        return probe

    def unit_test_run(self):
        if self._unit_run is not None:
            return self._unit_run
        result = self.run([self.tools["swift"], "test"], timeout=600)
        stdout = result.stdout
        stderr = result.stderr
        combined = stdout + "\n" + stderr
        log_path = self.artifacts / "unit-tests-{}.log".format(self.run_id)
        try:
            log_path.write_text(
                "$ {} test\nexit={}\n\n{}\n\nSTDERR:\n{}\n".format(
                    self.tools["swift"], result.code, stdout, stderr
                ),
                encoding="utf-8",
            )
        except OSError:
            pass
        failed_cases = re.findall(r"Test Case '([^']+)' failed", combined)
        xctest = [
            (int(count), int(failures))
            for count, failures in re.findall(
                r"Executed (\d+) tests?, with (\d+) failures?", combined
            )
        ]
        swift_testing = [
            (int(count), passed == "passed")
            for count, passed in re.findall(
                r"Test run with (\d+) tests? (passed|failed)", combined
            )
        ]
        count = 0
        failures = 0
        if xctest:
            count, failures = xctest[-1]
        if swift_testing:
            testing_count, testing_passed = swift_testing[-1]
            count = max(count, testing_count)
            if not testing_passed:
                failures = max(failures, 1)
        suites = sorted(set(re.findall(r"Test Suite '([^']+)'", combined)))
        self._unit_run = {
            "result": result,
            "combined": combined,
            "count": count,
            "failures": failures,
            "suites": suites,
            "xctest": xctest,
            "swift_testing": swift_testing,
            "failedCases": failed_cases,
            "logPath": str(log_path),
        }
        return self._unit_run

    def test_sources(self):
        paths = []
        tests_dir = REPO / "Tests"
        if tests_dir.is_dir():
            paths = sorted(tests_dir.rglob("*.swift"))
        return paths

    # ==================================================================
    # Environment checks
    # ==================================================================

    def check_E01(self):
        path = self.tools["adb"]
        return bool(path), "adb={} (MOTOMIRROR_ADB, PATH, Homebrew, Android SDK)".format(
            path or "NOT FOUND"
        )

    def check_E02(self):
        if not self.tools["adb"]:
            return False, "adb not found"
        result = self.run([self.tools["adb"], "version"], timeout=20)
        text = result.combined
        return (
            result.ok and "Android Debug Bridge" in text,
            result.evidence(),
        )

    def check_E03(self):
        path = self.tools["scrcpy"]
        return bool(path), "scrcpy={} (MOTOMIRROR_SCRCPY, PATH, Homebrew)".format(
            path or "NOT FOUND"
        )

    def check_E04(self):
        if not self.tools["scrcpy"]:
            return False, "scrcpy not found"
        result = self.run([self.tools["scrcpy"], "--version"], timeout=20)
        text = result.combined
        match = re.search(r"scrcpy\s+(\d+\.\d+\.\d+)", text)
        version = match.group(1) if match else None
        return (
            result.ok and version == "5.0.1",
            "{}\nreported version: {}".format(result.evidence(700), version),
        )

    def check_E05(self):
        path = self.tools["ffmpeg"]
        return bool(path), "ffmpeg={}".format(path or "NOT FOUND")

    def check_E06(self):
        if not self.tools["ffmpeg"]:
            return False, "ffmpeg not found"
        result = self.run([self.tools["ffmpeg"], "-version"], timeout=20)
        return (
            result.ok and "ffmpeg version" in result.combined,
            result.evidence(700),
        )

    def check_E07(self):
        if self.tools["ffprobe"]:
            result = self.run([self.tools["ffprobe"], "-version"], timeout=20)
            return result.ok, result.evidence(600)
        if self.tools["ffmpeg"]:
            return (
                True,
                "ffprobe missing; harness will parse media with the ffmpeg -i fallback at {}"
                .format(self.tools["ffmpeg"]),
            )
        return False, "neither ffprobe nor ffmpeg is available"

    def check_E08(self):
        version = "{}.{}.{}".format(*sys.version_info[:3])
        return (
            sys.version_info >= (3, 9),
            "{} at {} (requires Python >= 3.9)".format(version, sys.executable),
        )

    def check_E09(self):
        if not self.tools["adb"]:
            return False, "adb not found"
        start = self.run([self.tools["adb"], "start-server"], timeout=40)
        devices = self.run([self.tools["adb"], "devices"], timeout=25)
        return (
            start.ok and devices.ok,
            "start-server:\n{}\ndevices:\n{}".format(
                start.evidence(500), devices.evidence(700)
            ),
        )

    def check_E10(self):
        required = [
            REPO / "Package.swift",
            REPO / "Sources" / "MotoMirrorCore",
            REPO / "Sources" / "MotoMirror",
            REPO / "Sources" / "MotoMirrorCLI" / "main.swift",
            REPO / "Tests",
            REPO / "verify" / "verify.py",
            REPO / "scripts" / "verify.sh",
        ]
        missing = [str(path.relative_to(REPO)) for path in required if not path.exists()]
        return (
            not missing,
            "repo={}; missing={}".format(REPO, missing or "none"),
        )

    # ==================================================================
    # Build checks
    # ==================================================================

    def check_B01(self):
        result = self.run([self.tools["swift"], "build"], timeout=900)
        return result.ok, result.evidence(1400)

    def check_B02(self):
        path = self.binary_paths("debug") / "motomirrorctl"
        ok = path.is_file() and os.access(str(path), os.X_OK)
        return ok, "path={} mode={}".format(
            path, oct(path.stat().st_mode & 0o777) if path.exists() else "missing"
        )

    def check_B03(self):
        path = self.binary_paths("debug") / "MotoMirror"
        ok = path.is_file() and os.access(str(path), os.X_OK)
        return ok, "path={} mode={}".format(
            path, oct(path.stat().st_mode & 0o777) if path.exists() else "missing"
        )

    def check_B04(self):
        result = self.run([self.tools["swift"], "build", "-c", "release"], timeout=900)
        return result.ok, result.evidence(1400)

    def check_B05(self):
        path = self.binary_paths("release") / "motomirrorctl"
        ok = path.is_file() and os.access(str(path), os.X_OK)
        return ok, "path={} mode={}".format(
            path, oct(path.stat().st_mode & 0o777) if path.exists() else "missing"
        )

    def check_B06(self):
        path = self.binary_paths("release") / "MotoMirror"
        ok = path.is_file() and os.access(str(path), os.X_OK)
        return ok, "path={} mode={}".format(
            path, oct(path.stat().st_mode & 0o777) if path.exists() else "missing"
        )

    def check_B07(self):
        bundle = self.find_app_bundle()
        return bool(bundle), "bundle={}".format(bundle or "MotoMirror.app NOT FOUND")

    def check_B08(self):
        bundle, plist = self.app_plist()
        required_keys = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundleName"]
        missing = [key for key in required_keys if not plist.get(key)]
        return (
            not missing,
            "{} Info.plist keys={} missing={}".format(
                bundle, sorted(plist.keys()), missing or "none"
            ),
        )

    def check_B09(self):
        _bundle, plist = self.app_plist()
        identifier = str(plist.get("CFBundleIdentifier") or "")
        valid = bool(re.match(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$", identifier))
        return valid, "CFBundleIdentifier={!r}".format(identifier)

    def check_B10(self):
        _bundle, plist = self.app_plist()
        short_version = str(plist.get("CFBundleShortVersionString") or "")
        build_version = str(plist.get("CFBundleVersion") or "")
        return (
            bool(short_version or build_version),
            "CFBundleShortVersionString={!r} CFBundleVersion={!r}".format(
                short_version, build_version
            ),
        )

    def check_B11(self):
        bundle, plist = self.app_plist()
        icon_name = plist.get("CFBundleIconFile") or plist.get("CFBundleIconName")
        resources = bundle / "Contents" / "Resources"
        icons = []
        if resources.is_dir():
            icons = sorted(str(path.relative_to(bundle)) for path in resources.rglob("*.icns"))
        return (
            bool(icon_name or icons),
            "CFBundleIconFile={!r} CFBundleIconName={!r} icns={}".format(
                plist.get("CFBundleIconFile"), plist.get("CFBundleIconName"), icons or "none"
            ),
        )

    def check_B12(self):
        bundle = self.find_app_bundle()
        if bundle is None:
            return False, "no app bundle to sign"
        if not shutil.which("codesign"):
            return False, "codesign is not available"
        result = self.run(
            ["codesign", "--verify", "--deep", "--strict", str(bundle)], timeout=45
        )
        return result.ok, result.evidence(900)

    # ==================================================================
    # Unit test checks
    # ==================================================================

    def check_U01(self):
        run = self.unit_test_run()
        result = run["result"]
        return (
            result.ok,
            "swift test exit={} seconds={:.1f}\n{}".format(
                result.code, result.seconds, result.evidence(1200)
            ),
        )

    def check_U02(self):
        run = self.unit_test_run()
        return (
            run["count"] >= 20,
            "parsed test count={} (requires >= 20)\n{}".format(
                run["count"], truncate(run["combined"], 1200)
            ),
        )

    def check_U03(self):
        run = self.unit_test_run()
        return (
            run["failures"] == 0,
            "parsed failures={} failed_cases={} log={}".format(
                run["failures"], run.get("failedCases") or "none", run.get("logPath")
            ),
        )

    def check_U04(self):
        run = self.unit_test_run()
        text = run["combined"]
        passed_banner = bool(
            re.search(r"Test Suite 'All tests' passed", text)
            or re.search(r"Test run with \d+ tests? passed", text)
        )
        failed_banner = bool(
            re.search(r"Test Suite 'All tests' failed", text)
            or re.search(r"Test run with \d+ tests? failed", text)
            or re.search(r"\bTEST FAILED\b", text)
        )
        return passed_banner and not failed_banner, "passed_banner={} failed_banner={}".format(
            passed_banner, failed_banner
        )

    def test_source_contains(self, *needles):
        sources = self.test_sources()
        hits = []
        for path in sources:
            try:
                text = path.read_text(errors="replace").lower()
            except OSError:
                continue
            if all(needle.lower() in text for needle in needles):
                hits.append(str(path.relative_to(REPO)))
        return bool(hits), "test files={} matches={}".format(len(sources), hits or "none")

    def check_U05(self):
        ok, evidence = self.test_source_contains("parser")
        output_hit = bool(re.search(r"(?i)parser", self.unit_test_run()["combined"]))
        return ok and output_hit, evidence + "; output_mentions_parser={}".format(output_hit)

    def check_U06(self):
        ok, evidence = self.test_source_contains("scrcpy")
        return ok, evidence

    def check_U07(self):
        required = [
            "testRejectsInvalidHostnames",
            "testRejectsPortsOutsideRange",
            "testRejectsInvalidPairingCodes",
        ]
        source_text = ""
        for path in self.test_sources():
            try:
                source_text += path.read_text(errors="replace")
            except OSError:
                continue
        combined = self.unit_test_run()["combined"]
        hits = [
            name for name in required
            if name in source_text and name in combined
        ]
        return (
            len(hits) == len(required),
            "required_validation_tests={} matched_in_source_and_output={}".format(
                required, hits
            ),
        )

    def check_U08(self):
        sources = self.test_sources()
        hits = []
        for path in sources:
            try:
                text = path.read_text(errors="replace").lower()
            except OSError:
                continue
            if "runner" in text or "processrunner" in text:
                hits.append(str(path.relative_to(REPO)))
        return bool(hits), "runner test files={}".format(hits or "none")

    def check_U09(self):
        sources = self.test_sources()
        hits = []
        for path in sources:
            try:
                text = path.read_text(errors="replace").lower()
            except OSError:
                continue
            if "controller" in text or "session" in text or "scrcpycontrolling" in text:
                hits.append(str(path.relative_to(REPO)))
        return bool(hits), "controller/session test files={}".format(hits or "none")

    def check_U10(self):
        sources = self.test_sources()
        return len(sources) >= 3, "test source files={}: {}".format(
            len(sources), [str(path.relative_to(REPO)) for path in sources]
        )

    def check_U11(self):
        run = self.unit_test_run()
        return (
            run["count"] > 0,
            "parsed test count={} from swift test output".format(run["count"]),
        )

    def check_U12(self):
        run = self.unit_test_run()
        result = run["result"]
        return (
            not result.timed_out and result.seconds < 600,
            "swift test completed in {:.1f}s (timeout 600s)".format(result.seconds),
        )

    # ==================================================================
    # App/UI checks
    # ==================================================================

    def check_A01(self):
        result, path = self.base_snapshot()
        ok = result.ok and path.is_file() and path.stat().st_size > 0
        return ok, result.evidence(1200) + "\npath={} exists={}".format(
            path, path.exists()
        )

    def check_A02(self):
        _result, path = self.base_snapshot()
        header = png_header(path)
        return True, "PNG signature valid; IHDR={}".format(header)

    def check_A03(self):
        _result, path = self.base_snapshot()
        header = png_header(path)
        return (
            header["width"] >= 800 and header["height"] >= 600,
            "dimensions={}x{} (requires >= 800x600)".format(
                header["width"], header["height"]
            ),
        )

    def check_A04(self):
        _result, path = self.base_snapshot()
        size = path.stat().st_size
        return size > 20 * 1024, "bytes={} (requires > 20 KB)".format(size)

    def check_A05(self):
        _result, path = self.base_snapshot()
        header = png_stats(path)
        return (
            bool(header.get("nonBlank")),
            "uniqueColors={} channelRange={} variance={}".format(
                header.get("uniqueColors"), header.get("channelRange"),
                header.get("variance")
            ),
        )

    def check_A06(self):
        _result, path = self.base_snapshot()
        header = png_stats(path)
        colors = header.get("uniqueColors") or 0
        return colors >= 32, "sampled unique colors={} (requires >= 32)".format(colors)

    def snapshot_variant(self, state):
        result, path = self.demo_snapshot(state)
        if not (result.ok and path.is_file() and path.stat().st_size > 0):
            return False, "state={} failed: {}".format(state, result.evidence(900))
        header = png_header(path)
        stats = png_stats(path)
        ok = (
            header["width"] >= 800
            and header["height"] >= 600
            and path.stat().st_size > 10 * 1024
            and bool(stats.get("nonBlank"))
        )
        return ok, (
            "state={} path={} dimensions={}x{} bytes={} uniqueColors={}".format(
                state, path, header["width"], header["height"],
                path.stat().st_size, stats.get("uniqueColors")
            )
        )

    def check_A07(self):
        return self.snapshot_variant("connected")

    def check_A08(self):
        return self.snapshot_variant("empty")

    def check_A09(self):
        return self.snapshot_variant("unauthorized")

    def check_A10(self):
        return self.snapshot_variant("setup")

    def check_A11(self):
        hashes = {}
        for state in ("connected", "empty", "unauthorized", "setup"):
            result, path = self.demo_snapshot(state)
            if not (result.ok and path.is_file() and path.stat().st_size > 0):
                return False, "state={} snapshot missing after retry: {}".format(
                    state, result.evidence(700)
                )
            hashes[state] = sha256_file(path)
        distinct = len(set(hashes.values()))
        return distinct == 4, "distinct demo snapshots={} hashes={}".format(
            distinct, {state: digest[:12] for state, digest in hashes.items()}
        )

    def check_A12(self):
        executable = self.app_executable()
        result = self.run(["file", str(executable)], timeout=20)
        text = result.stdout
        return (
            "Mach-O" in text,
            "path={} file={}".format(executable, text.strip() or result.stderr.strip()),
        )

    # ==================================================================
    # Device basics (live)
    # ==================================================================

    def check_D01(self):
        wait = max(0, self.args.wait_for_device)
        device, devices, result = self.select_device(wait)
        if device is None:
            return False, "no usable device after waiting {}s:\n{}".format(
                wait, result.evidence(1200) if result else "adb unavailable"
            )
        self.set_device(device)
        self.ctx["waited_serial"] = device["serial"]
        return True, "waited={}s serial={} model={} transport={}\n{}".format(
            wait, device["serial"], device.get("model"), device["transport"],
            result.evidence(900),
        )

    def check_D02(self):
        serial = self.require_serial()
        payload, _result = self.cli_json(["devices", "--json"], timeout=30)
        if not isinstance(payload, list):
            return False, "devices --json did not return an array: {!r}".format(payload)
        match = next(
            (entry for entry in payload if entry.get("serial") == serial), None
        )
        return (
            match is not None and match.get("state") == "device",
            "serial={} entry={}".format(serial, match),
        )

    def check_D03(self):
        serial = self.require_serial()
        device = self.ctx.get("device") or {}
        model = device.get("model")
        details = self.details()
        model_text = str(details.get("model") or model or "").replace("_", " ").lower()
        serialized = str(details.get("serial") or serial)
        if self.args.target == "moto":
            ok = "moto" in model_text and "g85" in model_text
            return ok, "target=moto model={!r} detailsModel={!r} serial={} (requires moto + g85)".format(
                model, details.get("model"), serialized
            )
        return bool(model_text), "target=any model={!r} detailsModel={!r} serial={}".format(
            model, details.get("model"), serialized
        )

    def check_D04(self):
        self.require_serial()
        device = self.ctx.get("device") or {}
        transport = device.get("transport")
        serial = device.get("serial", "")
        model = str(device.get("model") or "").replace("_", " ").lower()
        if self.args.target == "moto":
            model_ok = "moto" in model and "g85" in model
            ok = transport in ("usb", "wireless") and model_ok
            return ok, (
                "target=moto transport={} model={!r} serial={} "
                "(requires USB or wireless and moto g85)"
            ).format(transport, device.get("model"), serial)
        if serial.startswith("emulator-"):
            return True, "target=any emulator transport={} serial={}".format(transport, serial)
        return transport in ("usb", "wireless"), (
            "target=any transport={} serial={}".format(transport, serial)
        )

    def check_D05(self):
        details = self.details()
        version = details.get("androidVersion")
        return bool(version), "androidVersion={!r}".format(version)

    def check_D06(self):
        details = self.details()
        raw = details.get("sdk")
        try:
            sdk = int(raw)
        except (TypeError, ValueError):
            return False, "sdk={!r} is not an integer".format(raw)
        return sdk >= 30, "sdk={} (requires Android 11 / API 30 or newer)".format(sdk)

    def check_D07(self):
        details = self.details()
        abi = details.get("abi")
        return bool(abi), "abi={!r}".format(abi)

    def check_D08(self):
        battery = self.details().get("battery") or {}
        level = battery.get("level")
        ok = isinstance(level, int) and 0 <= level <= 100
        return ok, "battery.level={!r}".format(level)

    def check_D09(self):
        battery = self.details().get("battery") or {}
        status = battery.get("status")
        temperature = battery.get("temperatureCelsius")
        voltage = battery.get("voltageMillivolts")
        ok = (
            bool(status)
            and isinstance(temperature, (int, float))
            and 0 < temperature < 80
            and isinstance(voltage, int)
            and 2500 < voltage < 5500
        )
        return ok, "status={!r} temperatureCelsius={!r} voltageMillivolts={!r}".format(
            status, temperature, voltage
        )

    def check_D10(self):
        storage = self.details().get("storage") or {}
        total = storage.get("totalBytes")
        available = storage.get("availableBytes")
        used = storage.get("usedBytes")
        fraction = storage.get("usedFraction")
        arithmetic_ok = False
        fraction_ok = False
        expected_used = None
        expected_fraction = None
        if (
            isinstance(total, int) and total > 0
            and isinstance(available, int) and 0 <= available <= total
            and isinstance(used, int) and used >= 0
        ):
            expected_used = total - available
            arithmetic_ok = abs(used - expected_used) <= 1024
            expected_fraction = used / total
            if isinstance(fraction, (int, float)):
                fraction_ok = abs(fraction - expected_fraction) <= 0.001
        ok = (
            isinstance(fraction, (int, float)) and 0 <= fraction <= 1
            and arithmetic_ok and fraction_ok
        )
        return ok, (
            "storage={} expected_used={} expected_usedFraction={!r} "
            "used_arithmetic_ok={} fraction_ok={}"
        ).format(storage, expected_used, expected_fraction, arithmetic_ok, fraction_ok)

    def check_D11(self):
        screen = self.details().get("screen") or {}
        width = screen.get("width")
        height = screen.get("height")
        density = screen.get("density")
        ok = (
            isinstance(width, int) and width > 0
            and isinstance(height, int) and height > 0
            and isinstance(density, int) and density > 0
        )
        return ok, "screen={}".format(screen)

    def check_D12(self):
        result, path = self.screenshot_file()
        header = png_header(path)
        return True, result.evidence(800) + "\nPNG header={}".format(header)

    def check_D13(self):
        _result, path = self.screenshot_file()
        header = png_header(path)
        return (
            header["width"] >= 800 and header["height"] >= 600,
            "screenshot dimensions={}x{} (requires >= 800x600)".format(
                header["width"], header["height"]
            ),
        )

    def check_D14(self):
        _result, path = self.screenshot_file()
        stats = png_stats(path)
        return (
            bool(stats.get("nonBlank")),
            "screenshot bytes={} uniqueColors={} channelRange={} variance={}".format(
                path.stat().st_size, stats.get("uniqueColors"),
                stats.get("channelRange"), stats.get("variance")
            ),
        )

    def check_D15(self):
        serial = self.require_serial()
        adb = self.tools["adb"]
        wake = self.run(
            [adb, "-s", serial, "shell", "input", "keyevent", "KEYCODE_WAKEUP"],
            timeout=25,
        )
        home = self.run(
            [adb, "-s", serial, "shell", "input", "keyevent", "KEYCODE_HOME"],
            timeout=25,
        )
        return wake.ok and home.ok, "wake:\n{}\nhome:\n{}".format(
            wake.evidence(500), home.evidence(500)
        )

    def check_D16(self):
        serial = self.require_serial()
        adb = self.tools["adb"]
        remote = "/sdcard/motomirror_ui_dump.xml"
        evidence = []
        # uiautomator can be killed by the device's low-memory killer under
        # load. Retry the real dump before treating it as a product failure.
        for attempt in range(1, 4):
            result = self.run(
                [adb, "-s", serial, "exec-out", "uiautomator", "dump", "/dev/tty"],
                timeout=45,
            )
            evidence.append("attempt {} direct:\n{}".format(attempt, result.evidence(600)))
            if result.ok and "<hierarchy" in result.stdout:
                return True, "\n".join(evidence)
            dump = self.run(
                [adb, "-s", serial, "shell", "uiautomator", "dump", remote], timeout=45
            )
            fetch = self.run([adb, "-s", serial, "exec-out", "cat", remote], timeout=30)
            cleanup = self.run([adb, "-s", serial, "shell", "rm", "-f", remote], timeout=20)
            evidence.append(
                "attempt {} fallback dump:\n{}\nfetch:\n{}\ncleanup_exit={}".format(
                    attempt, dump.evidence(500), fetch.evidence(700), cleanup.code
                )
            )
            if fetch.ok and "<hierarchy" in fetch.stdout and "package=" in fetch.stdout:
                return True, "\n".join(evidence)
            if attempt < 3:
                time.sleep(2)
        return False, "\n".join(evidence)

    # ==================================================================
    # Mirroring (live)
    # ==================================================================

    def screen_dimensions(self):
        screen = self.details().get("screen") or {}
        width = int(screen.get("width") or 0)
        height = int(screen.get("height") or 0)
        if width <= 0 or height <= 0:
            raise RuntimeError(
                "device details do not include usable screen dimensions: {!r}".format(screen)
            )
        return width, height

    def start_motion(self, seconds, serial=None):
        """Force display changes so scrcpy emits frames during a recording."""
        serial = serial or self.require_serial()
        adb = self.tools["adb"]
        try:
            width, height = self.screen_dimensions()
        except Exception:
            width, height = 0, 0
        y = int(height * 0.6)
        left = int(width * 0.2)
        right = int(width * 0.8)
        stop = threading.Event()

        def worker():
            self.run(
                [adb, "-s", serial, "shell", "input", "keyevent", "KEYCODE_WAKEUP"],
                timeout=20,
            )
            self.run(
                [adb, "-s", serial, "shell", "input", "keyevent", "KEYCODE_HOME"],
                timeout=20,
            )
            deadline = time.time() + max(1.0, seconds)
            direction = 0
            while width > 0 and height > 0 and time.time() < deadline and not stop.is_set():
                if direction % 2 == 0:
                    start_x, end_x = right, left
                else:
                    start_x, end_x = left, right
                self.run(
                    [
                        adb, "-s", serial, "shell", "input", "swipe",
                        str(start_x), str(y), str(end_x), str(y), "180",
                    ],
                    timeout=15,
                )
                direction += 1
                stop.wait(1.25)

        thread = threading.Thread(target=worker, name="motomirror-motion", daemon=True)
        thread.start()
        return stop, thread

    def session_seconds(self, result):
        match = re.search(r"after ([0-9]+(?:\.[0-9]+)?)s", result.stdout)
        if match:
            return float(match.group(1))
        return result.seconds

    def video_dimensions_match_device(self, video):
        if not video:
            return False, "no video stream"
        try:
            screen_width, screen_height = self.screen_dimensions()
        except Exception as exc:
            return False, "cannot verify dimensions: {}".format(exc)
        width = int(video.get("width") or 0)
        height = int(video.get("height") or 0)
        if width <= 0 or height <= 0:
            return False, "video dimensions are missing: {}x{}".format(width, height)
        tolerance = 8
        portrait = (
            abs(width - screen_width) <= tolerance
            and abs(height - screen_height) <= tolerance
        )
        landscape = (
            abs(width - screen_height) <= tolerance
            and abs(height - screen_width) <= tolerance
        )
        # Some Android encoders cannot encode the native panel size and scrcpy
        # applies a uniform scale (for example 1080x2400 -> 864x1920). Accept
        # only a same-aspect, non-upscaled image in either orientation.
        device_ratio = screen_width / screen_height
        video_ratio = width / height
        portrait_aspect_ok = abs(video_ratio - device_ratio) <= 0.01
        landscape_aspect_ok = abs(video_ratio - (1.0 / device_ratio)) <= 0.01
        # Reject tiny same-aspect thumbnails: a uniform encoder scale must keep
        # at least half of the panel in each dimension.
        scaled_portrait = (
            portrait_aspect_ok and width <= screen_width + tolerance
            and height <= screen_height + tolerance
            and width >= screen_width * 0.5
            and height >= screen_height * 0.5
        )
        scaled_landscape = (
            landscape_aspect_ok and width <= screen_height + tolerance
            and height <= screen_width + tolerance
            and width >= screen_height * 0.5
            and height >= screen_width * 0.5
        )
        scaled = scaled_portrait or scaled_landscape
        return (
            portrait or landscape or scaled,
            "video={}x{} device={}x{} portrait={} landscape={} "
            "same_aspect_scaled={} video_ratio={:.4f} device_ratio={:.4f}".format(
                width, height, screen_width, screen_height, portrait, landscape,
                scaled, video_ratio, device_ratio
            ),
        )

    def run_mirror(self, label, arguments, timeout, motion_seconds):
        serial = self.require_serial()
        # Wake/unlock and let the phone's video encoder fully release from the
        # previous session before starting another MP4.
        self.run(
            [self.tools["adb"], "-s", serial, "shell", "input", "keyevent", "KEYCODE_WAKEUP"],
            timeout=20,
        )
        self.run(
            [self.tools["adb"], "-s", serial, "shell", "wm", "dismiss-keyguard"],
            timeout=20,
        )
        time.sleep(2.0)
        stop, motion = self.start_motion(motion_seconds, serial=serial)
        try:
            result = self.run_cli(
                ["mirror", "--serial", serial] + arguments, timeout=timeout
            )
        finally:
            stop.set()
            motion.join(timeout=5)
        log_path = self.artifacts / "{}_session.log".format(label)
        try:
            log_path.write_text(
                result.evidence(12000) + "\n\nSTDOUT:\n" + result.stdout + "\n\nSTDERR:\n" + result.stderr
            )
        except OSError:
            pass
        return result

    def main_mirror(self):
        if self._mirror_main is None:
            path = self.artifacts / "mirror.mp4"
            result = self.run_mirror(
                "mirror",
                ["--headless", "--duration", "8", "--record", str(path)],
                timeout=180,
                motion_seconds=9.5,
            )
            self._mirror_main = (result, path)
        return self._mirror_main

    def second_mirror(self):
        if self._mirror_second is None:
            path = self.artifacts / "mirror2.mp4"
            result = self.run_mirror(
                "mirror2",
                ["--headless", "--duration", "8", "--record", str(path)],
                timeout=180,
                motion_seconds=9.5,
            )
            self._mirror_second = (result, path)
        return self._mirror_second

    def no_audio_mirror(self):
        if self._mirror_no_audio is None:
            path = self.artifacts / "mirror_no_audio.mp4"
            result = self.run_mirror(
                "mirror_no_audio",
                ["--headless", "--no-audio", "--duration", "8", "--record", str(path)],
                timeout=180,
                motion_seconds=9.5,
            )
            self._mirror_no_audio = (result, path)
        return self._mirror_no_audio

    def limits_mirror(self):
        if self._mirror_limits is None:
            path = self.artifacts / "mirror_limits.mp4"
            result = self.run_mirror(
                "mirror_limits",
                [
                    "--headless", "--duration", "6", "--max-size", "720",
                    "--max-fps", "30", "--record", str(path),
                ],
                timeout=150,
                motion_seconds=7.5,
            )
            self._mirror_limits = (result, path)
        return self._mirror_limits

    def check_M01(self):
        result, _path = self.main_mirror()
        return result.ok, result.evidence(1500)

    def check_M02(self):
        _result, path = self.main_mirror()
        size = path.stat().st_size if path.is_file() else 0
        return size > 20 * 1024, "recording={} bytes={} (requires > 20 KB)".format(path, size)

    def check_M03(self):
        _result, path = self.main_mirror()
        probe = self.probe_media(path)
        video = probe.get("video") or {}
        frames = video.get("frames")
        ok = probe["ok"] and isinstance(frames, int) and frames > 0
        return ok, "recording={} probe_ok={} frames={!r} video={}".format(
            path, probe["ok"], frames, video
        )

    def check_M04(self):
        _result, path = self.main_mirror()
        probe = self.probe_media(path)
        video = probe.get("video") or {}
        return (
            video.get("codec") == "h264",
            "video codec={!r} stream={}".format(video.get("codec"), video),
        )

    def check_M05(self):
        result, path = self.main_mirror()
        seconds = self.session_seconds(result)
        return (
            result.ok and seconds >= 7.0,
            "wall-clock mirror session={:.1f}s (requested 8s), recording={} exists={}".format(
                seconds, path, path.exists()
            ),
        )

    def check_M06(self):
        _result, path = self.main_mirror()
        video = self.probe_media(path).get("video") or {}
        width = video.get("width") or 0
        matches, detail = self.video_dimensions_match_device(video)
        return width > 0 and matches, "video width={} {}".format(width, detail)

    def check_M07(self):
        _result, path = self.main_mirror()
        video = self.probe_media(path).get("video") or {}
        height = video.get("height") or 0
        matches, detail = self.video_dimensions_match_device(video)
        return height > 0 and matches, "video height={} {}".format(height, detail)

    def check_M08(self):
        _result, path = self.main_mirror()
        video = self.probe_media(path).get("video") or {}
        fps = video.get("fps")
        return (
            isinstance(fps, (int, float)) and fps > 0,
            "video fps={!r} (requires > 0)".format(fps),
        )

    def check_M09(self):
        _result, path = self.main_mirror()
        probe = self.probe_media(path)
        return probe["ok"] and probe["audio"], "audio_stream={} (recording must include audio)".format(
            probe["audio"]
        )

    def check_M10(self):
        result, _path = self.main_mirror()
        text = result.stdout + "\n" + result.stderr
        matches = re.findall(
            r"(?im)^\s*(?:ERROR|FATAL)\b.*$|\b(?:fatal error|panic|uncaught exception)\b.*",
            text,
        )
        return not matches, "offending_lines={}".format(matches[:10] or "none")

    def check_M11(self):
        result, _path = self.second_mirror()
        return result.ok, result.evidence(1400)

    def check_M12(self):
        result, path = self.second_mirror()
        probe = self.probe_media(path)
        video = probe.get("video") or {}
        frames = video.get("frames")
        seconds = self.session_seconds(result)
        matches, detail = self.video_dimensions_match_device(video)
        ok = (
            result.ok
            and probe["ok"]
            and video.get("codec") == "h264"
            and isinstance(frames, int)
            and frames > 0
            and matches
            and seconds >= 7.0
        )
        return ok, "second recording={} wall_clock={:.1f}s codec={!r} frames={!r} {}".format(
            path, seconds, video.get("codec"), frames, detail
        )

    def check_M13(self):
        serial = self.require_serial()
        result, devices = self.adb_devices()
        match = next((device for device in devices if device["serial"] == serial), None)
        if match is not None and match["state"] == "device":
            return True, "device after mirroring={} \n{}".format(
                match, result.evidence(700)
            )
        cached_model = (self.ctx.get("device") or {}).get("model")
        alias = next(
            (
                device for device in devices
                if device["state"] == "device"
                and cached_model
                and (device.get("model") or "").lower().replace("_", " ")
                == cached_model.lower().replace("_", " ")
            ),
            None,
        )
        return (
            alias is not None,
            "device after mirroring={} alias={} \n{}".format(
                match, alias, result.evidence(700)
            ),
        )

    def check_M14(self):
        serial = self.require_serial()
        result = self.run(["ps", "-axo", "pid=,ppid=,comm=,args="], timeout=20)
        own_pids = {str(os.getpid()), str(os.getppid())}
        offenders = []
        for line in result.stdout.splitlines():
            parts = line.split(None, 3)
            if len(parts) < 3:
                continue
            pid, ppid, comm = parts[0], parts[1], parts[2]
            args = parts[3] if len(parts) > 3 else ""
            if pid in own_pids:
                continue
            # Only a real scrcpy executable counts. A shell, Python process,
            # pkill, log, or argument that merely contains "scrcpy" must not
            # match.
            comm_name = os.path.basename(comm).lower()
            argv0 = args.split(None, 1)[0] if args else ""
            argv0_name = os.path.basename(argv0).lower() if argv0 else ""
            if comm_name == "scrcpy" or argv0_name == "scrcpy":
                offenders.append(
                    "pid={} ppid={} comm={} args={}".format(pid, ppid, comm, args)
                )
        return (
            not offenders,
            "real scrcpy executable processes={} serial={}\nps evidence:\n{}".format(
                offenders[:10] or "none", serial, result.evidence(1200)
            ),
        )

    def check_M15(self):
        result, path = self.no_audio_mirror()
        size = path.stat().st_size if path.is_file() else 0
        return result.ok and size > 0, result.evidence(900) + "\nrecording={} bytes={}".format(
            path, size
        )

    def check_M16(self):
        _result, path = self.no_audio_mirror()
        probe = self.probe_media(path)
        video = probe.get("video") or {}
        frames = video.get("frames")
        ok = (
            probe["ok"]
            and isinstance(frames, int)
            and frames > 0
            and not probe["audio"]
        )
        return ok, "no-audio recording={} probe_ok={} frames={!r} audio_stream={}".format(
            path, probe["ok"], frames, probe["audio"]
        )

    def check_M17(self):
        result, path = self.limits_mirror()
        size = path.stat().st_size if path.is_file() else 0
        return result.ok and size > 0, result.evidence(900) + "\nrecording={} bytes={}".format(
            path, size
        )

    def check_M18(self):
        result, path = self.limits_mirror()
        probe = self.probe_media(path)
        video = probe.get("video") or {}
        frames = video.get("frames")
        width = int(video.get("width") or 0)
        height = int(video.get("height") or 0)
        longest = max(width, height)
        fps = video.get("fps")
        seconds = self.session_seconds(result)
        dimensions_ok = longest > 0 and abs(longest - 720) <= 2
        ok = (
            result.ok
            and probe["ok"]
            and isinstance(frames, int)
            and frames > 0
            and dimensions_ok
            and isinstance(fps, (int, float))
            and 0 < fps <= 30.5
            and seconds >= 5.0
        )
        return ok, (
            "max-size/max-fps recording width={} height={} longest={} fps={!r} "
            "frames={!r} wall_clock={:.1f}s (requires longest edge 720, fps <= 30)"
        ).format(width, height, longest, fps, frames, seconds)

    # ==================================================================
    # Wireless (live)
    # ==================================================================

    def is_emulator(self):
        cached = self.ctx.get("is_emulator")
        if cached is not None:
            return cached
        serial = self.require_serial()
        emulator = serial.startswith("emulator-")
        if not emulator:
            result = self.run(
                [self.tools["adb"], "-s", serial, "shell", "getprop", "ro.kernel.qemu"],
                timeout=15,
            )
            emulator = result.stdout.strip() == "1"
        self.ctx["is_emulator"] = emulator
        return emulator

    def is_wireless_target(self):
        cached = self.ctx.get("is_wireless_target")
        if cached is not None:
            return cached
        serial = self.require_serial()
        wireless = ":" in serial or is_mdns_serial(serial)
        self.ctx["is_wireless_target"] = wireless
        return wireless

    def wireless_port(self):
        return 5555 if self.is_emulator() else 5559

    def mdns_connect_endpoint(self, serial, timeout=10):
        adb = self.tools["adb"]
        wanted = serial.split("._adb-tls-connect._tcp")[0].lower()
        deadline = time.time() + timeout
        evidence = []
        while True:
            result = self.run([adb, "mdns", "services"], timeout=20)
            evidence.append(result.evidence(800))
            services = []
            for line in result.stdout.splitlines():
                parts = line.split()
                if len(parts) < 3:
                    continue
                if "_adb-tls-connect._tcp" not in parts[1].lower():
                    continue
                endpoint = parts[-1]
                if ":" not in endpoint:
                    continue
                host, port_text = endpoint.rsplit(":", 1)
                try:
                    port = int(port_text)
                except ValueError:
                    continue
                services.append((parts[0].lower(), host, port))
            match = next(
                (service for service in services if service[0] == wanted), None
            )
            if match is None and services:
                match = services[0]
            if match is not None:
                return match[1], match[2], "\n".join(evidence)
            if time.time() >= deadline:
                return None, None, "\n".join(evidence)
            time.sleep(1.0)

    def wireless_endpoint(self):
        if self.is_wireless_target():
            serial = self.require_serial()
            if is_mdns_serial(serial):
                host, port, evidence = self.mdns_connect_endpoint(serial, timeout=10)
                return host, port, evidence
            if ":" in serial:
                host, port_text = serial.rsplit(":", 1)
                try:
                    port = int(port_text)
                except ValueError:
                    return None, None, "serial has no parseable host:port: {}".format(serial)
                return host, port, "current wireless serial={}".format(serial)
        if self.is_emulator():
            return "127.0.0.1", 5555, "emulator: host loopback maps guest adbd on 5555"
        host, evidence = self.wireless_host()
        return host, 5559, evidence

    def wireless_host(self):
        if self._wireless_host_cache is not None:
            return self._wireless_host_cache
        serial = self.require_serial()
        adb = self.tools["adb"]
        commands = [
            [adb, "-s", serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"],
            [adb, "-s", serial, "shell", "ip", "route"],
            [adb, "-s", serial, "shell", "getprop", "dhcp.wlan0.ipaddress"],
        ]
        evidence = []
        host = None
        for command in commands:
            result = self.run(command, timeout=25)
            evidence.append(result.evidence(500))
            for pattern in (r"inet\s+(\d+\.\d+\.\d+\.\d+)", r"\bsrc\s+(\d+\.\d+\.\d+\.\d+)",
                            r"^\s*(\d+\.\d+\.\d+\.\d+)\s*$"):
                match = re.search(pattern, result.stdout, re.MULTILINE)
                if match:
                    candidate = match.group(1)
                    if candidate not in ("0.0.0.0", "127.0.0.1"):
                        host = candidate
                        break
            if host:
                break
        self._wireless_host_cache = (host, "\n".join(evidence))
        return self._wireless_host_cache

    def wireless_serial(self):
        if self.is_wireless_target():
            return self.require_serial()
        host, port, _evidence = self.wireless_endpoint()
        if not host:
            raise RuntimeError("could not determine the phone Wi-Fi IP address")
        return "{}:{}".format(host, port)

    def wait_for_serial(self, serial, timeout):
        deadline = time.time() + timeout
        result = None
        devices = []
        while True:
            result, devices = self.adb_devices()
            if any(
                device["serial"] == serial and device["state"] == "device"
                for device in devices
            ):
                return True, result, devices
            if time.time() >= deadline:
                return False, result, devices
            time.sleep(1.0)

    def wait_for_wireless_online(self, serial, endpoint, timeout):
        deadline = time.time() + timeout
        result = None
        devices = []
        while True:
            result, devices = self.adb_devices()
            serial_online = any(
                device["serial"] == serial and device["state"] == "device"
                for device in devices
            )
            endpoint_online = bool(endpoint) and any(
                device["serial"] == endpoint and device["state"] == "device"
                for device in devices
            )
            if serial_online or endpoint_online:
                return True, result, devices
            if time.time() >= deadline:
                return False, result, devices
            time.sleep(1.0)

    def prove_wireless_mode(self, serial, port, endpoint, timeout=15):
        """Prove TCP mode is active without trusting the tcpip command text.

        Primary proof: service.adb.tcp.port equals the requested port.
        Secondary proof: adb connect endpoint followed by get-state == device.
        """
        adb = self.tools["adb"]
        deadline = time.time() + timeout
        property_value = None
        property_result = None
        connect_result = None
        state_result = None
        endpoint_ok = False
        while True:
            if property_value != str(port):
                property_result = self.run(
                    [
                        adb, "-s", serial, "shell", "getprop",
                        "service.adb.tcp.port",
                    ],
                    timeout=20,
                )
                property_value = property_result.stdout.strip()
            connect_result = self.run([adb, "connect", endpoint], timeout=40)
            state_result = self.run([adb, "-s", endpoint, "get-state"], timeout=20)
            endpoint_ok = (
                state_result.ok and state_result.stdout.strip() == "device"
            )
            if property_value == str(port) or endpoint_ok:
                break
            if time.time() >= deadline:
                break
            time.sleep(1.0)
        evidence = "\n".join(
            [
                property_result.evidence(500) if property_result else "property: not read",
                "service.adb.tcp.port={!r} requested={!r}".format(property_value, str(port)),
                connect_result.evidence(500) if connect_result else "connect: not attempted",
                state_result.evidence(500) if state_result else "get-state: not attempted",
                "property_proves_tcp_mode={} endpoint_state_device={}".format(
                    property_value == str(port), endpoint_ok
                ),
            ]
        )
        return property_value == str(port), endpoint_ok, evidence

    def check_W01(self):
        serial = self.require_serial()
        if self.is_wireless_target():
            online, device_result, devices = self.wait_for_serial(serial, 15)
            if is_mdns_serial(serial):
                host, endpoint_port, mdns_evidence = self.mdns_connect_endpoint(
                    serial, timeout=10
                )
                service_ok = host is not None
            elif ":" in serial:
                host, endpoint_text = serial.rsplit(":", 1)
                try:
                    endpoint_port = int(endpoint_text)
                    service_ok = True
                except ValueError:
                    host, endpoint_port, service_ok = None, None, False
                mdns_evidence = "current wireless serial={}".format(serial)
            else:
                host, endpoint_port, service_ok = None, None, False
                mdns_evidence = "unrecognized wireless serial"
            ok = online and service_ok
            return ok, (
                "already-wireless target: adb tcpip was not run\n"
                "serial={} state_device={} mdns_connect_service={}:{}\n"
                "devices={}\n{}"
            ).format(
                serial, online, host, endpoint_port, devices,
                device_result.evidence(700) + "\n" + mdns_evidence
            )

        port = self.wireless_port()
        # Record the Wi-Fi address before adb restarts adbd in TCP mode. USB
        # often drops for a few seconds here, and losing the address would make
        # the rest of the wireless checks unreportable. Emulators use the host
        # loopback mapping on 5555 instead of a guest Wi-Fi IP.
        if not self.is_emulator():
            self.wireless_host()
        result = self.run_cli(
            ["wireless", "tcpip", "--serial", serial, "--port", str(port)], timeout=60
        )
        evidence = [result.evidence(900)]

        if result.ok:
            restored, restore_result, devices = self.wait_for_serial(serial, 15)
            evidence.append(
                "port={} serial restored within 15s={} devices={}\n{}".format(
                    port, restored, devices, restore_result.evidence(600)
                )
            )
            if restored:
                return True, "\n".join(evidence)

        # The command can fail with "error: closed" when adbd is already in TCP
        # mode. Prove the mode from the device property or a live endpoint.
        host, endpoint_port, endpoint_evidence = self.wireless_endpoint()
        endpoint = "{}:{}".format(host, endpoint_port) if host else "<unknown>"
        property_ok = False
        endpoint_ok = False
        proof = "wireless endpoint unavailable"
        if host:
            property_ok, endpoint_ok, proof = self.prove_wireless_mode(
                serial, port, endpoint, timeout=15
            )
            if endpoint_ok:
                self.ctx["wireless_serial"] = endpoint
        else:
            proof = endpoint_evidence
        ok = property_ok or endpoint_ok
        evidence.append(
            "tcpip command exit={} port={} property_proof={} endpoint_proof={}\n{}".format(
                result.code, port, property_ok, endpoint_ok, proof
            )
        )
        return ok, "\n".join(evidence)

    def check_W02(self):
        if self.is_wireless_target():
            serial = self.require_serial()
            online, poll_result, devices = self.wait_for_serial(serial, 15)
            host, endpoint_port, mdns_evidence = self.wireless_endpoint()
            self.ctx["wireless_serial"] = serial
            self.ctx["wireless_connected"] = bool(online)
            return online, (
                "already-wireless target: adb connect was not run\n"
                "serial={} online={} endpoint={}:{}\n"
                "devices={}\n{}\n{}"
            ).format(
                serial, online, host, endpoint_port, devices,
                poll_result.evidence(700), mdns_evidence
            )

        host, port, host_evidence = self.wireless_endpoint()
        if not host:
            return False, "no Wi-Fi IP address; host detection evidence:\n" + host_evidence
        serial = self.require_serial()
        self.wait_for_serial(serial, 15)
        result = self.run_cli(
            ["wireless", "connect", "--host", host, "--port", str(port)], timeout=60
        )
        wireless = "{}:{}".format(host, port)
        connected, poll_result, devices = self.wait_for_serial(wireless, 15)
        self.ctx["wireless_serial"] = wireless
        self.ctx["wireless_connected"] = bool(result.ok and connected)
        return (
            result.ok and connected,
            "connect:\n{}\nwireless_serial={} listed={} devices={}\n{}".format(
                result.evidence(800), wireless, connected, devices,
                poll_result.evidence(700)
            ),
        )

    def check_W03(self):
        try:
            wireless = self.ctx.get("wireless_serial") or self.wireless_serial()
        except Exception as exc:
            host, port, host_evidence = self.wireless_endpoint()
            return False, "no wireless serial ({}); endpoint={}:{}; evidence:\n{}".format(
                exc, host, port, host_evidence
            )
        payload, _result = self.cli_json(["devices", "--json"], timeout=30)
        match = next(
            (entry for entry in payload if entry.get("serial") == wireless), None
        )
        if self.is_wireless_target() and is_mdns_serial(wireless):
            # ADB's mDNS serial has no colon; the core parser currently reports
            # transport "unknown". The mDNS serial itself proves wireless.
            transport_ok = match is not None and match.get("transport") in (
                "wireless", "unknown"
            )
            return (
                match is not None
                and match.get("state") == "device"
                and transport_ok,
                "wireless_serial={} entry={} (mDNS wireless transport)".format(
                    wireless, match
                ),
            )
        return (
            match is not None
            and match.get("state") == "device"
            and match.get("transport") == "wireless",
            "wireless_serial={} entry={}".format(wireless, match),
        )

    def check_W04(self):
        try:
            wireless = self.ctx.get("wireless_serial") or self.wireless_serial()
        except Exception as exc:
            host, port, host_evidence = self.wireless_endpoint()
            return False, "no wireless serial ({}); endpoint={}:{}; evidence:\n{}".format(
                exc, host, port, host_evidence
            )
        path = self.artifacts / "wireless.png"
        result = self.run_cli(
            ["screenshot", "--serial", wireless, "--out", str(path)], timeout=90
        )
        if not result.ok:
            return False, result.evidence(900)
        stats = png_stats(path)
        return bool(stats.get("nonBlank")), result.evidence(600) + "\nscreenshot={} dims={}x{} uniqueColors={}".format(
            path, stats["width"], stats["height"], stats.get("uniqueColors")
        )

    def wireless_mirror(self):
        if self._wireless_mirror is None:
            wireless = self.ctx.get("wireless_serial") or self.wireless_serial()
            path = self.artifacts / "wireless.mp4"
            stop, motion = self.start_motion(7.5, serial=wireless)
            try:
                result = self.run_cli(
                    [
                        "mirror", "--serial", wireless, "--headless", "--duration", "6",
                        "--record", str(path),
                    ],
                    timeout=150,
                )
            finally:
                stop.set()
                motion.join(timeout=5)
            try:
                (self.artifacts / "wireless_session.log").write_text(
                    result.evidence(12000) + "\n\nSTDOUT:\n" + result.stdout
                    + "\n\nSTDERR:\n" + result.stderr
                )
            except OSError:
                pass
            self._wireless_mirror = (result, path)
        return self._wireless_mirror

    def check_W05(self):
        try:
            result, _path = self.wireless_mirror()
        except Exception as exc:
            host, port, host_evidence = self.wireless_endpoint()
            return False, "could not run wireless mirror ({}); endpoint={}:{}; evidence:\n{}".format(
                exc, host, port, host_evidence
            )
        return result.ok, result.evidence(1400)

    def check_W06(self):
        try:
            result, path = self.wireless_mirror()
        except Exception as exc:
            host, port, host_evidence = self.wireless_endpoint()
            return False, "could not run wireless mirror ({}); endpoint={}:{}; evidence:\n{}".format(
                exc, host, port, host_evidence
            )
        probe = self.probe_media(path)
        video = probe.get("video") or {}
        frames = video.get("frames")
        seconds = self.session_seconds(result)
        matches, detail = self.video_dimensions_match_device(video)
        ok = (
            result.ok
            and probe["ok"]
            and video.get("codec") == "h264"
            and isinstance(frames, int)
            and frames > 0
            and matches
            and seconds >= 5.0
        )
        return ok, "wireless recording={} wall_clock={:.1f}s codec={!r} frames={!r} {}".format(
            path, seconds, video.get("codec"), frames, detail
        )

    def check_W07(self):
        if not self.ctx.get("wireless_connected"):
            return False, "wireless connection was never established; nothing to disconnect"
        serial = self.ctx.get("wireless_serial") or self.require_serial()

        if self.is_wireless_target():
            host, port, mdns_evidence = self.wireless_endpoint()
            endpoint = "{}:{}".format(host, port) if host else None
            result = self.run(
                [self.tools["adb"], "disconnect", serial], timeout=30
            )
            evidence = [
                "already-wireless mDNS disconnect: {}".format(serial),
                result.evidence(800),
                "endpoint={} mdns={}".format(endpoint, mdns_evidence),
            ]
            clean = result.ok or any(
                token in result.combined.lower()
                for token in ("no such device", "not found", "no matching connection")
            )
            online, poll_result, devices = self.wait_for_wireless_online(
                serial, endpoint, 15
            )
            evidence.append(
                "after 15s online={} devices={}\n{}".format(
                    online, devices, poll_result.evidence(600)
                )
            )
            if not online and endpoint:
                connect = self.run(
                    [self.tools["adb"], "connect", endpoint], timeout=40
                )
                evidence.append(
                    "reconnect attempt:\n{}".format(connect.evidence(600))
                )
                online, poll_result, devices = self.wait_for_wireless_online(
                    serial, endpoint, 15
                )
                evidence.append(
                    "after reconnect online={} devices={}\n{}".format(
                        online, devices, poll_result.evidence(600)
                    )
                )
            self.ctx["wireless_recovered"] = online
            self.ctx["wireless_disconnect_clean"] = clean
            return clean and online, "\n".join(evidence)

        host, port, _host_evidence = self.wireless_endpoint()
        if not host:
            return False, "no Wi-Fi IP address for disconnect"
        result = self.run_cli(
            ["wireless", "disconnect", "--host", host, "--port", str(port)],
            timeout=45,
        )
        return result.ok, result.evidence(900)

    def check_W08(self):
        if not self.ctx.get("wireless_connected"):
            return False, "wireless connection was never established; device state cannot be verified"
        wireless = self.ctx.get("wireless_serial")
        if not wireless:
            wireless = self.require_serial()

        if self.is_wireless_target():
            host, port, mdns_evidence = self.wireless_endpoint()
            endpoint = "{}:{}".format(host, port) if host else None
            online, poll_result, devices = self.wait_for_wireless_online(
                wireless, endpoint, 5
            )
            connect_evidence = ""
            if not online and endpoint:
                connect = self.run(
                    [self.tools["adb"], "connect", endpoint], timeout=40
                )
                connect_evidence = connect.evidence(700)
                online, poll_result, devices = self.wait_for_wireless_online(
                    wireless, endpoint, 15
                )
            evidence = (
                "wireless disconnect clean={} final online={}\n"
                "serial={} endpoint={} devices={}\n{}\n{}\n{}"
            ).format(
                self.ctx.get("wireless_disconnect_clean"),
                online,
                wireless,
                endpoint,
                devices,
                poll_result.evidence(700),
                connect_evidence,
                mdns_evidence,
            )
            return online, evidence

        deadline = time.time() + 15
        result = None
        devices = []
        while True:
            result, devices = self.adb_devices()
            present = any(device["serial"] == wireless for device in devices)
            if not present:
                return True, "wireless serial {} removed; devices={}\n{}".format(
                    wireless, devices, result.evidence(600)
                )
            if time.time() >= deadline:
                return False, "wireless serial {} still listed after disconnect: {}\n{}".format(
                    wireless, devices, result.evidence(600)
                )
            time.sleep(1.0)

    # ==================================================================
    # Docs checks
    # ==================================================================

    def readme_text(self):
        path = REPO / "README.md"
        if not path.is_file():
            raise RuntimeError("README.md does not exist")
        return path.read_text(errors="replace")

    def check_DOC01(self):
        path = REPO / "README.md"
        exists = path.is_file()
        size = path.stat().st_size if exists else 0
        return exists and size > 1000, "README.md exists={} bytes={}".format(exists, size)

    def check_DOC02(self):
        text = self.readme_text()
        headings = re.findall(r"(?m)^#{1,6}\s+(.+?)\s*$", text)
        install_headings = [
            heading for heading in headings
            if re.match(
                r"^(install|installation|setup|quick\s+start|getting\s+started)\b",
                heading.strip().lower(),
            )
        ]
        commands = [
            command for command in ("make setup", "./scripts/setup.sh", "brew install")
            if command in text.lower()
        ]
        ok = bool(install_headings) and bool(commands)
        return ok, "install_or_setup_headings={} install_commands={} uninstall_excluded={}".format(
            install_headings or "none",
            commands or "none",
            not any("uninstall" in heading.lower() for heading in install_headings),
        )

    def check_DOC03(self):
        text = self.readme_text().lower()
        ok = "usb debugging" in text and "developer options" in text
        return ok, "mentions_usb_debugging={} mentions_developer_options={}".format(
            "usb debugging" in text, "developer options" in text
        )

    def check_DOC04(self):
        text = self.readme_text().lower()
        ok = "wireless" in text and ("pair" in text or "adb connect" in text)
        return ok, "mentions_wireless={} mentions_pairing_or_connect={}".format(
            "wireless" in text, "pair" in text or "adb connect" in text
        )

    def check_DOC05(self):
        text = self.readme_text().lower()
        ok = any(word in text for word in ("troubleshoot", "troubleshooting", "faq", "common problems"))
        return ok, "troubleshooting section present={}".format(ok)

    def check_DOC06(self):
        readme = self.readme_text().lower()
        verify_readme = REPO / "verify" / "README.md"
        verify_text = verify_readme.read_text(errors="replace").lower() if verify_readme.is_file() else ""
        readme_ok = "verify" in readme or "verification" in readme
        headings_ok = all(
            needle in verify_text
            for needle in ("threshold", "artifact", "environment", "device", "mirroring", "wireless")
        )
        return (
            readme_ok and verify_readme.is_file() and headings_ok,
            "README verification section={} verify/README.md exists={} required_headings={}".format(
                readme_ok, verify_readme.is_file(), headings_ok
            ),
        )

    # ==================================================================
    # Robustness checks
    # ==================================================================

    def check_R01(self):
        result = self.run_cli(
            ["info", "--serial", "motomirror-missing-device", "--json"], timeout=60
        )
        text = result.combined.lower()
        clear_error = "not connected" in text or "not found" in text or "missing" in text
        crashed = "fatal error" in text or "signal" in text or "traceback" in text
        ok = result.code != 0 and bool(result.stderr.strip()) and clear_error and not crashed
        return ok, "missing-device command must fail clearly without crashing\n" + result.evidence(900)

    def check_R02(self):
        result = self.run_cli(["doctor", "--json"], timeout=45)
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            return False, "doctor --json did not parse: {}\n{}".format(
                exc, result.evidence(900)
            )
        required = {
            "adb", "scrcpy", "ffmpeg", "adbVersion", "scrcpyVersion",
            "deviceCount", "ok",
        }
        missing = sorted(required - set(payload.keys()))
        return not missing, "exit={} keys={} missing={} payload={}".format(
            result.code, sorted(payload.keys()), missing or "none", payload
        )

    def check_R03(self):
        result = self.run_cli(["definitely-not-a-command"], timeout=30)
        ok = result.code != 0 and bool(result.stderr.strip())
        return ok, result.evidence(900)

    def check_R04(self):
        # A real pairing needs the six-digit code shown on the phone. Without
        # one, verify the CLI rejects an invalid code before touching adb.
        result = self.run_cli(
            [
                "wireless", "pair", "--host", "127.0.0.1", "--port", "5555",
                "--code", "12345",
            ],
            timeout=30,
        )
        text = result.stderr.lower()
        ok = result.code != 0 and ("6-digit" in text or "pairing code" in text)
        return ok, "invalid pairing code rejection (not a pairing success)\n" + result.evidence(900)

    def check_R05(self):
        script = REPO / "scripts" / "verify.sh"
        executable = script.is_file() and os.access(str(script), os.X_OK)
        syntax = self.run(["bash", "-n", str(script)], timeout=30)
        return executable and syntax.ok, "script={} executable={} bash -n exit={}\n{}".format(
            script, executable, syntax.code, syntax.evidence(600)
        )

    def check_R06(self):
        result = self.run_cli(["version"], timeout=30)
        ok = result.ok and "1.0.0" in result.stdout
        return ok, result.evidence(600)

    # ==================================================================
    # Registration
    # ==================================================================

    def register_checks(self):
        environment = "Environment"
        self.add("E01", environment, "adb is installed", False, self.check_E01)
        self.add("E02", environment, "adb version runs", False, self.check_E02)
        self.add("E03", environment, "scrcpy is installed", False, self.check_E03)
        self.add("E04", environment, "scrcpy is 5.0.1", False, self.check_E04)
        self.add("E05", environment, "ffmpeg is installed", False, self.check_E05)
        self.add("E06", environment, "ffmpeg version runs", False, self.check_E06)
        self.add("E07", environment, "ffprobe or ffmpeg fallback available", False, self.check_E07)
        self.add("E08", environment, "Python is 3.9 or newer", False, self.check_E08)
        self.add("E09", environment, "adb server responds", False, self.check_E09)
        self.add("E10", environment, "Repository layout is complete", False, self.check_E10)

        build = "Build"
        self.add("B01", build, "swift build (debug) succeeds", False, self.check_B01)
        self.add("B02", build, "Debug motomirrorctl exists and is executable", False, self.check_B02)
        self.add("B03", build, "Debug MotoMirror app binary exists", False, self.check_B03)
        self.add("B04", build, "swift build -c release succeeds", False, self.check_B04)
        self.add("B05", build, "Release motomirrorctl exists and is executable", False, self.check_B05)
        self.add("B06", build, "Release MotoMirror app binary exists", False, self.check_B06)
        self.add("B07", build, "MotoMirror.app bundle exists", False, self.check_B07)
        self.add("B08", build, "Info.plist is valid with required keys", False, self.check_B08)
        self.add("B09", build, "App bundle identifier is valid", False, self.check_B09)
        self.add("B10", build, "App version is declared", False, self.check_B10)
        self.add("B11", build, "App icon is declared or bundled", False, self.check_B11)
        self.add("B12", build, "App bundle signature verifies", False, self.check_B12)

        unit = "Unit tests"
        self.add("U01", unit, "swift test exits zero", False, self.check_U01)
        self.add("U02", unit, "At least 20 tests execute", False, self.check_U02)
        self.add("U03", unit, "Zero test failures", False, self.check_U03)
        self.add("U04", unit, "All-tests banner reports success", False, self.check_U04)
        self.add("U05", unit, "Parser tests are present", False, self.check_U05)
        self.add("U06", unit, "scrcpy command tests are present", False, self.check_U06)
        self.add("U07", unit, "Validation tests cover hosts, ports, and pairing codes", False, self.check_U07)
        self.add("U08", unit, "Process runner tests are present", False, self.check_U08)
        self.add("U09", unit, "Controller/session tests are present", False, self.check_U09)
        self.add("U10", unit, "At least three test source files exist", False, self.check_U10)
        self.add("U11", unit, "Test count is parsed from output", False, self.check_U11)
        self.add("U12", unit, "Test run completes inside its timeout", False, self.check_U12)

        app = "App/UI"
        self.add("A01", app, "App --snapshot exits zero", False, self.check_A01)
        self.add("A02", app, "Snapshot has a PNG signature", False, self.check_A02)
        self.add("A03", app, "Snapshot is at least 800x600", False, self.check_A03)
        self.add("A04", app, "Snapshot is larger than 20 KB", False, self.check_A04)
        self.add("A05", app, "Snapshot is not blank", False, self.check_A05)
        self.add("A06", app, "Snapshot has at least 32 sampled colors", False, self.check_A06)
        self.add("A07", app, "Demo connected snapshot renders", False, self.check_A07)
        self.add("A08", app, "Demo empty snapshot renders", False, self.check_A08)
        self.add("A09", app, "Demo unauthorized snapshot renders", False, self.check_A09)
        self.add("A10", app, "Demo setup snapshot renders", False, self.check_A10)
        self.add("A11", app, "Demo snapshots are visually distinct", False, self.check_A11)
        self.add("A12", app, "App executable is a Mach-O binary", False, self.check_A12)

        device = "Device basics"
        self.add("D01", device, "A usable device is present", True, self.check_D01)
        self.add("D02", device, "CLI devices JSON reports the device", True, self.check_D02)
        self.add("D03", device, "Device model matches the target", True, self.check_D03)
        self.add("D04", device, "Transport and model match the target", True, self.check_D04)
        self.add("D05", device, "Android version is readable", True, self.check_D05)
        self.add("D06", device, "SDK is Android 11 or newer", True, self.check_D06)
        self.add("D07", device, "ABI is readable", True, self.check_D07)
        self.add("D08", device, "Battery level is readable", True, self.check_D08)
        self.add("D09", device, "Battery status, temperature, voltage", True, self.check_D09)
        self.add("D10", device, "Storage totals are consistent", True, self.check_D10)
        self.add("D11", device, "Screen size and density are readable", True, self.check_D11)
        self.add("D12", device, "CLI screenshot writes a PNG", True, self.check_D12)
        self.add("D13", device, "Screenshot is at least 800x600", True, self.check_D13)
        self.add("D14", device, "Screenshot is not blank", True, self.check_D14)
        self.add("D15", device, "Input keyevent is injected", True, self.check_D15)
        self.add("D16", device, "UI hierarchy dump is readable", True, self.check_D16)

        mirroring = "Mirroring"
        self.add("M01", mirroring, "Headless mirror runs for 8 seconds", True, self.check_M01)
        self.add("M02", mirroring, "Mirror recording file is substantial", True, self.check_M02)
        self.add("M03", mirroring, "Recording contains video frames", True, self.check_M03)
        self.add("M04", mirroring, "Recording video codec is H.264", True, self.check_M04)
        self.add("M05", mirroring, "Mirror session stays alive for 8 seconds", True, self.check_M05)
        self.add("M06", mirroring, "Recording width matches the device", True, self.check_M06)
        self.add("M07", mirroring, "Recording height matches the device", True, self.check_M07)
        self.add("M08", mirroring, "Recording frame rate is non-zero", True, self.check_M08)
        self.add("M09", mirroring, "Recording includes an audio stream", True, self.check_M09)
        self.add("M10", mirroring, "Session logs contain no fatal errors", True, self.check_M10)
        self.add("M11", mirroring, "Second mirror session starts cleanly", True, self.check_M11)
        self.add("M12", mirroring, "Second recording is valid", True, self.check_M12)
        self.add("M13", mirroring, "Device stays connected after mirroring", True, self.check_M13)
        self.add("M14", mirroring, "No orphan scrcpy processes remain", True, self.check_M14)
        self.add("M15", mirroring, "No-audio mirror session runs", True, self.check_M15)
        self.add("M16", mirroring, "No-audio recording has no audio stream", True, self.check_M16)
        self.add("M17", mirroring, "Max-size and max-fps session runs", True, self.check_M17)
        self.add("M18", mirroring, "Max-size and max-fps limits are applied", True, self.check_M18)

        wireless = "Wireless"
        self.add("W01", wireless, "Wireless transport is established", True, self.check_W01)
        self.add("W02", wireless, "Wireless target is already connected", True, self.check_W02)
        self.add("W03", wireless, "CLI reports the wireless device", True, self.check_W03)
        self.add("W04", wireless, "Wireless screenshot is valid", True, self.check_W04)
        self.add("W05", wireless, "Mirror runs over wireless", True, self.check_W05)
        self.add("W06", wireless, "Wireless recording is valid H.264", True, self.check_W06)
        self.add("W07", wireless, "Wireless disconnect is clean", True, self.check_W07)
        self.add("W08", wireless, "Wireless device remains usable or recovers", True, self.check_W08)

        docs = "Docs"
        self.add("DOC01", docs, "README.md exists and is substantive", False, self.check_DOC01)
        self.add("DOC02", docs, "README has a real install/setup section", False, self.check_DOC02)
        self.add("DOC03", docs, "README documents USB debugging", False, self.check_DOC03)
        self.add("DOC04", docs, "README documents wireless pairing", False, self.check_DOC04)
        self.add("DOC05", docs, "README has troubleshooting guidance", False, self.check_DOC05)
        self.add("DOC06", docs, "Verification docs cover categories and artifacts", False, self.check_DOC06)

        robustness = "Robustness"
        self.add("R01", robustness, "CLI reports a missing device without crashing", False, self.check_R01)
        self.add("R02", robustness, "CLI doctor --json parses", False, self.check_R02)
        self.add("R03", robustness, "Unknown CLI command exits nonzero", False, self.check_R03)
        self.add("R04", robustness, "wireless pair rejects an invalid pairing code", False, self.check_R04)
        self.add("R05", robustness, "verify.sh is executable and syntactically valid", False, self.check_R05)
        self.add("R06", robustness, "CLI version command reports 1.0.0", False, self.check_R06)

        actual = Counter(check["category"] for check in self.checks)
        problems = []
        if len(self.checks) != 100:
            problems.append("expected 100 checks, registered {}".format(len(self.checks)))
        for category, expected in CATEGORY_COUNTS.items():
            if actual.get(category, 0) != expected:
                problems.append(
                    "{}: expected {}, registered {}".format(
                        category, expected, actual.get(category, 0)
                    )
                )
        if problems:
            raise SystemExit("HARNESS SELF-CHECK FAILED: " + "; ".join(problems))

    # -- execution and reporting ---------------------------------------

    def execute(self, check):
        base = {
            "id": check["id"],
            "category": check["category"],
            "title": check["title"],
            "status": "fail",
            "evidence": "",
            "weight": check["weight"],
        }
        if check["live"] and not self.args.live:
            base["status"] = "skip"
            base["evidence"] = "requires --live"
            return base
        started = time.time()
        try:
            ok, evidence = check["function"]()
            base["status"] = "pass" if ok else "fail"
            base["evidence"] = truncate(evidence)
        except Exception as exc:  # noqa: BLE001 - every check must fail closed
            base["status"] = "fail"
            base["evidence"] = truncate(
                "exception: {}: {}\n{}".format(
                    type(exc).__name__, exc, traceback.format_exc(limit=3)
                )
            )
        base["seconds"] = round(time.time() - started, 2)
        if self.args.verbose:
            print(
                "[{}] {} {} ({:.1f}s)".format(
                    base["id"], base["status"].upper(), check["title"], base["seconds"]
                )
            )
        return base

    def run_all(self):
        for check in self.checks:
            self.results[check["id"]] = self.execute(check)
        self.write_reports()
        self.print_summary()

    def ordered_results(self):
        return [self.results[check["id"]] for check in self.checks if check["id"] in self.results]

    def score(self):
        results = self.ordered_results()
        executed = [result for result in results if result["status"] != "skip"]
        passed = sum(1 for result in executed if result["status"] == "pass")
        failed = sum(1 for result in executed if result["status"] == "fail")
        skipped = sum(1 for result in results if result["status"] == "skip")
        total_weight_executed = sum(result["weight"] for result in executed)
        total_weight_passed = sum(
            result["weight"] for result in executed if result["status"] == "pass"
        )
        percent = (
            (total_weight_passed / total_weight_executed) * 100
            if total_weight_executed
            else 0.0
        )
        return {
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "executed": len(executed),
            "total": len(self.checks),
            "weightPassed": total_weight_passed,
            "weightExecuted": total_weight_executed,
            "percent": round(percent, 2),
            "threshold": self.args.threshold,
            "liveMode": bool(self.args.live),
            "gatePassed": (
                percent + 1e-9 >= self.args.threshold
                and failed == 0
                and (not self.args.live or skipped == 0)
            ),
        }

    def device_summary(self):
        details = self.ctx.get("details") or {}
        device = self.ctx.get("device") or {}
        serial = self.ctx.get("serial") or details.get("serial")
        if not serial:
            return None
        return {
            "serial": serial,
            "model": details.get("model") or device.get("model"),
            "manufacturer": details.get("manufacturer"),
            "androidVersion": details.get("androidVersion"),
            "sdk": details.get("sdk"),
            "transport": device.get("transport"),
            "target": self.args.target,
        }

    def artifact_list(self):
        items = []
        cutoff = self.start_time - 2.0
        if self.artifacts.is_dir():
            for path in sorted(self.artifacts.rglob("*")):
                if not path.is_file():
                    continue
                stat = path.stat()
                if stat.st_mtime < cutoff:
                    continue
                items.append(
                    {
                        "path": str(path.relative_to(REPO)),
                        "bytes": stat.st_size,
                        "sha256": sha256_file(path),
                    }
                )
        return items

    def report_payload(self):
        score = self.score()
        finished_at = datetime.now().astimezone().isoformat(timespec="seconds")
        title = "# MotoMirror Verification Report"
        lines = [
            title,
            "",
            "- Run ID: {}".format(self.run_id),
            "- Started: {}".format(self.started_at),
            "- Finished: {}".format(finished_at),
            "- Mode: {}".format("live" if self.args.live else "static"),
            "- Target: {}".format(self.args.target),
        ]
        device = self.device_summary()
        if device:
            lines.append(
                "- Device: {serial} — {model} (Android {android}, SDK {sdk}, {transport})".format(
                    serial=device.get("serial"),
                    model=device.get("model") or "unknown",
                    android=device.get("androidVersion") or "?",
                    sdk=device.get("sdk") or "?",
                    transport=device.get("transport") or "?",
                )
            )
        else:
            lines.append("- Device: none")
        if self.args.live:
            lines.append(
                "- Score: {weightPassed}/{weightExecuted} weighted checks ({percent}%)".format(
                    **score
                )
            )
        else:
            lines.append(
                "- Static score: {weightPassed}/{weightExecuted} executed checks ({percent}%); "
                "live score pending ({live} checks require --live)".format(
                    live=LIVE_CHECK_COUNT, **score
                )
            )
        lines.append(
            "- Threshold: {}% — {} (zero failed checks required; live mode also "
            "requires zero skipped checks)".format(
                score["threshold"], "PASS" if score["gatePassed"] else "FAIL"
            )
        )
        lines.append(
            "- Status counts: {} passed, {} failed, {} skipped".format(
                score["passed"], score["failed"], score["skipped"]
            )
        )
        lines.extend(["", "## Categories", "", "| Category | Passed | Failed | Skipped | Total |",
                      "| --- | ---: | ---: | ---: | ---: |"])
        results = self.ordered_results()
        for category in CATEGORY_COUNTS:
            subset = [result for result in results if result["category"] == category]
            lines.append(
                "| {} | {} | {} | {} | {} |".format(
                    category,
                    sum(1 for result in subset if result["status"] == "pass"),
                    sum(1 for result in subset if result["status"] == "fail"),
                    sum(1 for result in subset if result["status"] == "skip"),
                    len(subset),
                )
            )

        failed = [result for result in results if result["status"] == "fail"]
        lines.extend(["", "## Failed checks", ""])
        if failed:
            for result in failed:
                lines.extend(
                    [
                        "### {} — {} ({})".format(
                            result["id"], result["title"], result["category"]
                        ),
                        "",
                        "```",
                        result["evidence"],
                        "```",
                        "",
                    ]
                )
        else:
            lines.append("None.")
            lines.append("")

        lines.extend(
            [
                "## Checks",
                "",
                "| ID | Category | Status | Title |",
                "| --- | --- | --- | --- |",
            ]
        )
        for result in results:
            lines.append(
                "| {} | {} | {} | {} |".format(
                    result["id"], result["category"], result["status"], result["title"]
                )
            )

        lines.extend(["", "## Artifacts", ""])
        artifacts = self.artifact_list()
        if artifacts:
            for artifact in artifacts:
                lines.append(
                    "- `{}` ({} bytes, SHA256 `{}`)".format(
                        artifact["path"], artifact["bytes"], artifact["sha256"]
                    )
                )
        else:
            lines.append("- No artifacts produced.")
        lines.append("")

        payload = {
            "schema": 1,
            "runId": self.run_id,
            "startedAt": self.started_at,
            "finishedAt": finished_at,
            "generatedAt": finished_at,
            "mode": "live" if self.args.live else "static",
            "target": self.args.target,
            "device": device,
            "score": score,
            "checks": results,
            "artifacts": artifacts,
        }
        return "\n".join(lines), payload

    def write_reports(self):
        markdown, payload = self.report_payload()
        try:
            self.report_path.write_text(markdown, encoding="utf-8")
            self.json_path.write_text(
                json.dumps(payload, indent=2, sort_keys=False), encoding="utf-8"
            )
        except OSError as exc:
            print("ERROR: could not write reports: {}".format(exc), file=sys.stderr)

    def print_summary(self):
        score = self.score()
        results = self.ordered_results()
        print("")
        print(
            "{:<6} {:<14} {:<6} {}".format("ID", "CATEGORY", "STATUS", "TITLE")
        )
        print("-" * 100)
        for result in results:
            print(
                "{:<6} {:<14} {:<6} {}".format(
                    result["id"], result["category"], result["status"], result["title"]
                )
            )
        print("-" * 100)
        failures = [result for result in results if result["status"] == "fail"]
        if failures:
            print("")
            print("FAILED CHECKS ({}):".format(len(failures)))
            for result in failures:
                print("")
                print("[{}] {} — {}".format(result["id"], result["title"], result["category"]))
                print(result["evidence"])
        if self.args.live:
            print("")
            summary = dict(score)
            summary["status"] = "PASS" if score["gatePassed"] else "FAIL"
            print(
                "Live score: {weightPassed}/{weightExecuted} ({percent}%) — "
                "{failed} failed, {skipped} skipped — threshold {threshold}%: {status} "
                "(zero failed checks required)".format(**summary)
            )
        else:
            print("")
            print(
                "static score {}/{} ({:.2f}%), {} failed, {} skipped, live score pending "
                "({} checks require --live)".format(
                    score["weightPassed"], score["weightExecuted"], score["percent"],
                    score["failed"], score["skipped"], score["skipped"],
                )
            )
            print(
                "Threshold {}%: {} (zero failed checks required)".format(
                    score["threshold"], "PASS" if score["gatePassed"] else "FAIL"
                )
            )
        print("")
        print("Report:     {}".format(self.report_path))
        print("JSON:       {}".format(self.json_path))
        print("Artifacts:  {}".format(self.artifacts))
        print("Elapsed:    {:.1f}s".format(time.time() - self.start_time))

    def cleanup(self):
        serial = self.ctx.get("waited_serial") or self.ctx.get("serial")

        # An already-wireless phone must never be disconnected or put through
        # adb tcpip by cleanup. Ensure it is online, reconnecting the mDNS
        # service endpoint at most once if needed.
        if serial and (":" in serial or is_mdns_serial(serial)):
            host, port, _mdns = self.wireless_endpoint()
            endpoint = "{}:{}".format(host, port) if host else None
            online, result, devices = self.wait_for_wireless_online(
                serial, endpoint, 5
            )
            if not online and endpoint:
                self.run(
                    [self.tools["adb"], "connect", endpoint], timeout=40
                )
                self.wait_for_wireless_online(serial, endpoint, 15)
            return

        wireless = self.ctx.get("wireless_serial")
        if wireless:
            host = wireless.rsplit(":", 1)[0]
            try:
                self.run(
                    [self.tools["adb"], "disconnect", wireless], timeout=20
                )
            except Exception:
                pass
            try:
                port = wireless.rsplit(":", 1)[1]
            except IndexError:
                port = "5559"
            try:
                self.run_cli(
                    ["wireless", "disconnect", "--host", host, "--port", port],
                    timeout=20,
                )
            except Exception:
                pass

        # Leave an emulator in USB mode so a repeat run starts from a clean
        # transport instead of hitting "error: closed" on tcpip. Never change a
        # physical phone's transport.
        if serial and serial.startswith("emulator-"):
            for _attempt in range(2):
                result = self.run(
                    [self.tools["adb"], "-s", serial, "usb"], timeout=30
                )
                if result.ok:
                    break
                time.sleep(2.0)
            self.wait_for_serial(serial, 15)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="MotoMirror 100-check verification harness",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--live", action="store_true", help="execute all 100 checks against a device")
    parser.add_argument("--target", choices=["moto", "any"], default="any",
                        help="moto requires a Moto G85 on USB; any accepts emulators")
    parser.add_argument("--wait-for-device", type=int, default=0, metavar="SECONDS",
                        help="wait up to SECONDS for a usable device (default 0)")
    parser.add_argument("--threshold", type=int, default=99,
                        help="minimum passing percentage (default 99)")
    parser.add_argument("--json-out", default="verification/report.json",
                        help="JSON report path (default verification/report.json)")
    parser.add_argument("--report", default="verification/REPORT.md",
                        help="Markdown report path (default verification/REPORT.md)")
    parser.add_argument("--keep-artifacts", action="store_true",
                        help="keep previous artifacts instead of clearing before the run")
    parser.add_argument("--verbose", action="store_true", help="print each check as it finishes")
    args = parser.parse_args(argv)
    if not 0 <= args.threshold <= 100:
        parser.error("--threshold must be between 0 and 100")
    if args.wait_for_device < 0:
        parser.error("--wait-for-device must be zero or positive")
    return args


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    harness = Harness(args)
    try:
        harness.register_checks()
        harness.run_all()
        score = harness.score()
        return 0 if score["gatePassed"] else 1
    finally:
        harness.cleanup()


if __name__ == "__main__":
    sys.exit(main())
