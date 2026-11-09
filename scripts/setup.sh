#!/usr/bin/env bash
set -euo pipefail

find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

has_tool() {
    command -v "$1" >/dev/null 2>&1
}

missing=()
has_tool adb || missing+=("adb")
has_tool scrcpy || missing+=("scrcpy")

if (( ${#missing[@]} > 0 )); then
    printf 'Missing: %s\n' "${missing[*]}"
    if brew_path="$(find_brew)"; then
        echo "==> Installing scrcpy and android-platform-tools with Homebrew"
        "${brew_path}" install scrcpy android-platform-tools
        export PATH="$(dirname "${brew_path}"):${PATH}"
        hash -r
    else
        cat >&2 <<'EOF'
Homebrew is required to install the missing tools.
Install Homebrew from https://brew.sh, then run this script again.

If you prefer manual installs, install adb (Android platform-tools) and
scrcpy 5.x, and put both commands on your PATH.
EOF
        exit 1
    fi
fi

has_tool adb || {
    printf 'error: adb is still not on PATH after install\n' >&2
    printf 'Open a new terminal, or add /opt/homebrew/bin to PATH.\n' >&2
    exit 1
}
has_tool scrcpy || {
    printf 'error: scrcpy is still not on PATH after install\n' >&2
    printf 'Open a new terminal, or add /opt/homebrew/bin to PATH.\n' >&2
    exit 1
}

printf '\n==> Versions\n'
adb version | sed -n '1,2p'
scrcpy --version | sed -n '1p'

cat <<'EOF'

==> Next steps
1. On the phone: Settings > About phone > tap Build number 7 times.
2. Settings > System > Developer options > turn on USB debugging.
3. Connect a USB-C data cable and tap Allow on the phone.
4. Check the connection: adb devices -l
5. Build the app: make app
6. Open it: open dist/MotoMirror.app

Wireless debugging and troubleshooting: docs/SETUP-MOTO-G85.md
EOF
