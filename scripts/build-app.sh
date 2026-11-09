#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

APP_NAME="MotoMirror"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
BUNDLE_RESOURCES_DIR="${CONTENTS_DIR}/Resources"

INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
ICON_PNG="${ROOT_DIR}/Resources/AppIcon-1024.png"
ICON_ICNS="${ROOT_DIR}/Resources/AppIcon.icns"
ICON_ICONSET="${ROOT_DIR}/Resources/AppIcon.iconset"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

cd "${ROOT_DIR}"

command -v swift >/dev/null 2>&1 || fail "swift was not found. Install Xcode Command Line Tools with: xcode-select --install"
command -v plutil >/dev/null 2>&1 || fail "plutil was not found. Install Xcode Command Line Tools with: xcode-select --install"
command -v codesign >/dev/null 2>&1 || fail "codesign was not found. Install Xcode Command Line Tools with: xcode-select --install"
[[ -f "${INFO_PLIST}" ]] || fail "missing ${INFO_PLIST}"

make_icon() {
    if [[ ! -f "${ICON_PNG}" ]]; then
        echo "==> Drawing app icon"
        swift "${ROOT_DIR}/scripts/make-icon.swift" "${ICON_PNG}"
    fi

    if [[ -f "${ICON_ICNS}" && "${ICON_ICNS}" -nt "${ICON_PNG}" ]]; then
        return
    fi

    command -v sips >/dev/null 2>&1 || fail "sips was not found; it is required to build the app icon"
    command -v iconutil >/dev/null 2>&1 || fail "iconutil was not found; it is required to build the app icon"

    echo "==> Building AppIcon.icns"
    rm -rf "${ICON_ICONSET}"
    mkdir -p "${ICON_ICONSET}"
    for size in 16 32 128 256 512; do
        sips -z "${size}" "${size}" "${ICON_PNG}" \
            --out "${ICON_ICONSET}/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "${ICON_PNG}" \
            --out "${ICON_ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "${ICON_ICONSET}" -o "${ICON_ICNS}"
    rm -rf "${ICON_ICONSET}"
}

echo "==> Building ${APP_NAME} (release)"
swift build -c release --product "${APP_NAME}"

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
[[ -x "${BIN_PATH}" ]] || fail "release executable not found at ${BIN_PATH}"

make_icon

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${BUNDLE_RESOURCES_DIR}"
install -m 755 "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
install -m 644 "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"
install -m 644 "${ICON_ICNS}" "${BUNDLE_RESOURCES_DIR}/AppIcon.icns"

plutil -lint "${CONTENTS_DIR}/Info.plist"

echo "==> Signing ${APP_NAME}.app (ad hoc)"
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

printf 'Built %s\n' "${APP_DIR}"
