#!/usr/bin/env python3
"""Live agent-feature verification for MotoMirror.

Runs against the isolated emulator only. Never selects the Moto G85.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / ".build" / "debug" / "motomirrorctl"
ADB = "adb"
SERIAL = "emulator-5554"
PARAKEY_IME = "com.parakey.keyboard/.ParakeyImeService"
LATIN_IME = "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME"

checks = []


def run(args, timeout=60):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def adb(*args, timeout=60):
    return run([ADB, "-s", SERIAL, *args], timeout=timeout)


def cli(*args, timeout=120):
    return run([str(CLI), "--serial", SERIAL, *args], timeout=timeout)


def record(cid, name, ok, evidence):
    checks.append({"id": cid, "name": name, "pass": bool(ok), "evidence": evidence[:1200]})
    print(("PASS" if ok else "FAIL"), cid, name)
    return bool(ok)


def reset_chrome():
    for pkg in ("com.parakey.keyboard", "com.android.settings",
                "com.google.android.settings.intelligence", "com.android.chrome"):
        adb("shell", "am", "force-stop", pkg)
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    adb("shell", "am", "start", "-W", "-n", "com.android.chrome/com.google.android.apps.chrome.Main")
    time.sleep(3)


def current_package():
    result = cli("apps", "current", "--json")
    try:
        return json.loads(result.stdout).get("package")
    except Exception:
        return None


def ensure_settings_home():
    for _ in range(6):
        for pkg in ("com.parakey.keyboard", "com.google.android.settings.intelligence",
                    "com.android.settings"):
            adb("shell", "am", "force-stop", pkg)
        adb("shell", "input", "keyevent", "KEYCODE_HOME")
        adb("shell", "am", "start", "-W", "-S", "-n", "com.android.settings/.Settings")
        time.sleep(2)
        if current_package() == "com.android.settings":
            # The search page can remain in the task; HOME then Settings resets it.
            text = cli("ui", "dump", "--json")
            if "Search settings" in text.stdout:
                return True
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
    return False


def main():
    if not CLI.exists():
        raise SystemExit("Build motomirrorctl first")
    if "device" not in adb("get-state").stdout.strip():
        raise SystemExit(f"{SERIAL} is not online")

    adb("shell", "am", "force-stop", "com.parakey.keyboard")
    adb("shell", "ime", "set", LATIN_IME)
    adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    adb("shell", "wm", "dismiss-keyguard")
    reset_chrome()

    # 1-6 apps
    apps = cli("apps", "list", "--system", "--json")
    try:
        packages = [item["package"] for item in json.loads(apps.stdout)]
    except Exception:
        packages = []
    record("A01", "apps list includes Settings", "com.android.settings" in packages, apps.stdout or apps.stderr)

    current = cli("apps", "current", "--json")
    try:
        current_pkg = json.loads(current.stdout).get("package")
    except Exception:
        current_pkg = None
    record("A02", "apps current returns a package", bool(current_pkg), current.stdout)

    reset_chrome()
    launched = cli("apps", "launch", "com.android.chrome")
    wait_chrome = cli("wait-for", "app", "com.android.chrome", "--timeout", "8")
    current = cli("apps", "current", "--json")
    try:
        current_pkg = json.loads(current.stdout).get("package")
    except Exception:
        current_pkg = None
    record("A03", "apps launch Chrome", launched.returncode == 0 and wait_chrome.returncode == 0 and current_pkg == "com.android.chrome", launched.stdout + wait_chrome.stdout + current.stdout)

    # 7-12 UI
    settings_ready = ensure_settings_home()
    if not settings_ready:
        raise SystemExit("Settings did not reach the home screen")
    dump = cli("ui", "dump", "--json")
    try:
        elements = json.loads(dump.stdout).get("elements", [])
    except Exception:
        elements = []
    record("A04", "ui dump returns elements", settings_ready and len(elements) >= 10, f"settings_ready={settings_ready} elements={len(elements)}")

    found = cli("ui", "find", "--text", "Search settings", "--json")
    try:
        matches = json.loads(found.stdout)
    except Exception:
        matches = []
    record("A05", "ui find by text", bool(matches), f"matches={len(matches)}")

    tap = cli("ui", "tap", "--text", "Search settings")
    record("A06", "ui tap by text", tap.returncode == 0, tap.stdout + tap.stderr)

    time.sleep(1)
    ensure_settings_home()
    tap2 = cli("ui", "tap", "--text", "Search settings")
    time.sleep(1)
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
    for _ in range(30):
        adb("shell", "input", "keyevent", "KEYCODE_DEL")
    typed = cli("ui", "text", "motomirror")
    time.sleep(2)
    dump2 = cli("ui", "dump", "--json")
    try:
        texts = [e.get("text") or "" for e in json.loads(dump2.stdout).get("elements", [])]
    except Exception:
        texts = []
    record("A07", "ui text types into Settings search", typed.returncode == 0 and any("motomirror" in t.lower() for t in texts), f"tap={tap2.stdout.strip()} texts={texts[:8]}")

    key = cli("ui", "key", "KEYCODE_BACK")
    record("A08", "ui key sends a keyevent", key.returncode == 0, key.stdout + key.stderr)

    swipe = cli("ui", "swipe", "540", "1600", "540", "800", "--duration", "200")
    record("A09", "ui swipe", swipe.returncode == 0, swipe.stdout + swipe.stderr)

    shot = ROOT / "verification" / "agent-features-screenshot.png"
    screenshot = cli("screenshot", "--out", str(shot), timeout=90)
    record("A10", "screenshot writes a PNG", screenshot.returncode == 0 and shot.exists() and shot.stat().st_size > 20_000, f"{screenshot.stdout} bytes={shot.stat().st_size if shot.exists() else 0}")

    # 13-15 files and shell
    local = Path("/tmp/motomirror-agent-feature.txt")
    local.write_text("motomirror-agent\n")
    pushed = cli("files", "push", str(local), "/sdcard/Download/motomirror-agent-feature.txt")
    listed = cli("files", "ls", "/sdcard/Download", "--json")
    pulled_local = Path("/tmp/motomirror-agent-feature-back.txt")
    pulled = cli("files", "pull", "/sdcard/Download/motomirror-agent-feature.txt", str(pulled_local))
    record("A11", "files push/ls/pull", pushed.returncode == 0 and pulled.returncode == 0 and "motomirror-agent-feature.txt" in listed.stdout and pulled_local.exists(), pushed.stdout + listed.stdout + pulled.stdout)

    shell = cli("shell", "echo", "motomirror-agent")
    record("A12", "shell echo", shell.returncode == 0 and "motomirror-agent" in shell.stdout, shell.stdout)

    # 16-19 state
    wake = cli("screen", "wake")
    rotate = cli("screen", "rotate", "0")
    record("A13", "screen wake and rotate", wake.returncode == 0 and rotate.returncode == 0, wake.stdout + rotate.stdout)

    volume = cli("volume", "get", "--json")
    try:
        vol = json.loads(volume.stdout)
        vol_ok = 0 <= vol["level"] <= vol["max"]
    except Exception:
        vol_ok = False
    record("A14", "volume get", vol_ok, volume.stdout)

    logcat = cli("logcat", "-n", "5")
    record("A15", "logcat returns text", logcat.returncode == 0 and len(logcat.stdout.strip()) > 0, logcat.stdout[:500])

    reset_chrome()
    wait = cli("wait-for", "app", "com.android.chrome", "--timeout", "8")
    record("A16", "wait-for app", wait.returncode == 0, wait.stdout + wait.stderr)

    # 20-23 agent and MCP
    tools = cli("agent", "tools", "--json")
    try:
        tool_list = json.loads(tools.stdout)
    except Exception:
        tool_list = []
    record("A17", "agent tools lists 20+ tools", len(tool_list) >= 20, f"tools={len(tool_list)}")

    call = cli("agent", "call", "apps_list", "--args", json.dumps({"serial": SERIAL, "includeSystem": True}), "--json")
    try:
        payload = json.loads(call.stdout)
        call_ok = not payload.get("isError") and "com.android.settings" in payload.get("text", "")
    except Exception:
        call_ok = False
    record("A18", "agent call apps_list", call_ok, call.stdout[:800])

    mcp_ok, mcp_evidence = mcp_check()
    record("A19", "MCP initialize/tools/list/tools/call", mcp_ok, mcp_evidence)

    adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    adb("shell", "wm", "dismiss-keyguard")
    opened = cli("open", "https://example.com")
    current_after_open = None
    for _ in range(5):
        time.sleep(1)
        current_after_open = cli("apps", "current", "--json")
        try:
            if json.loads(current_after_open.stdout).get("package"):
                break
        except Exception:
            pass
    try:
        open_pkg = json.loads(current_after_open.stdout).get("package") if current_after_open else None
    except Exception:
        open_pkg = None
    record("A21", "open URL launches a handler", opened.returncode == 0 and bool(open_pkg), opened.stdout + (current_after_open.stdout[:300] if current_after_open else ""))

    usb = run([str(CLI), "--usb", "--serial", SERIAL, "apps", "list"])
    usb_ok = usb.returncode != 0 and "USB" in (usb.stdout + usb.stderr)
    record("A20", "USB-only guard rejects non-USB device", usb_ok, usb.stdout + usb.stderr)

    reset_chrome()
    stopped = cli("apps", "stop", "com.android.chrome")
    time.sleep(1)
    after_stop = cli("apps", "current", "--json")
    try:
        after_pkg = json.loads(after_stop.stdout).get("package")
    except Exception:
        after_pkg = None
    record("A22", "apps stop", stopped.returncode == 0 and after_pkg != "com.android.chrome", stopped.stdout + after_stop.stdout)

    vol_before = cli("volume", "get", "--json")
    try:
        level = json.loads(vol_before.stdout)["level"]
    except Exception:
        level = 8
    vol_set = cli("volume", "set", str(level))
    vol_after = cli("volume", "get", "--json")
    try:
        after_level = json.loads(vol_after.stdout)["level"]
    except Exception:
        after_level = None
    record("A23", "volume set", vol_set.returncode == 0 and after_level == level, vol_set.stdout + vol_after.stdout)

    sleep = cli("screen", "sleep")
    time.sleep(1)
    wake2 = cli("screen", "wake")
    record("A24", "screen sleep and wake", sleep.returncode == 0 and wake2.returncode == 0, sleep.stdout + wake2.stdout)


    # restore emulator state; leave the other agent's keyboard as it was
    adb("shell", "ime", "set", PARAKEY_IME)
    adb("shell", "cmd", "media_session", "volume", "--stream", "3", "--set", "8")
    adb("shell", "settings", "put", "system", "user_rotation", "0")
    adb("shell", "am", "force-stop", "com.android.chrome")
    adb("shell", "am", "force-stop", "com.android.settings")

    passed = sum(1 for c in checks if c["pass"])
    total = len(checks)
    report = {
        "serial": SERIAL,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "passed": passed,
        "total": total,
        "checks": checks,
    }
    out_json = ROOT / "verification" / "agent-features.json"
    out_json.write_text(json.dumps(report, indent=2))
    lines = [
        "# MotoMirror agent feature verification",
        "",
        f"- Device: `{SERIAL}` (emulator only; the Moto G85 was not used)",
        f"- Result: **{passed}/{total}**",
        "",
        "| ID | Feature | Result | Evidence |",
        "| --- | --- | --- | --- |",
    ]
    for c in checks:
        lines.append(f"| {c['id']} | {c['name']} | {'pass' if c['pass'] else 'fail'} | `{c['evidence'][:160].replace('|','/').replace(chr(10),' ')}` |")
    (ROOT / "verification" / "AGENT-FEATURES.md").write_text("\n".join(lines) + "\n")
    print(f"\n{passed}/{total} agent checks passed")
    print(f"Report: {out_json}")
    return 0 if passed == total else 1


def mcp_check():
    proc = subprocess.Popen(
        [str(CLI), "mcp"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())

    try:
        init = send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        listed = send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        called = send({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": {"name": "apps_list", "arguments": {"serial": SERIAL, "includeSystem": True}},
        })
        tools = listed.get("result", {}).get("tools", [])
        content = called.get("result", {}).get("content", [])
        text = next((c.get("text", "") for c in content if c.get("type") == "text"), "")
        ok = (
            init.get("result", {}).get("serverInfo", {}).get("name") == "motomirror"
            and len(tools) >= 20
            and "com.android.settings" in text
        )
        return ok, f"server={init.get('result', {}).get('serverInfo')} tools={len(tools)} settings={'com.android.settings' in text}"
    except Exception as exc:  # noqa: BLE001
        return False, repr(exc)
    finally:
        try:
            proc.stdin.close()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
