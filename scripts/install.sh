#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

OPEN_APP=0
for arg in "$@"; do
    case "${arg}" in
        --open)
            OPEN_APP=1
            ;;
        -h|--help)
            printf 'Usage: %s [--open]\n' "$(basename "$0")"
            exit 0
            ;;
        *)
            printf 'error: unknown option: %s\n' "${arg}" >&2
            printf 'Usage: %s [--open]\n' "$(basename "$0")" >&2
            exit 2
            ;;
    esac
done

[[ -n "${HOME:-}" ]] || {
    printf 'error: HOME is not set\n' >&2
    exit 1
}

SOURCE_APP="${ROOT_DIR}/dist/MotoMirror.app"
DEST_DIR="${HOME}/Applications"
DEST_APP="${DEST_DIR}/MotoMirror.app"

"${ROOT_DIR}/scripts/build-app.sh"

echo "==> Installing to ${DEST_APP}"
mkdir -p "${DEST_DIR}"
rm -rf "${DEST_APP}"
ditto "${SOURCE_APP}" "${DEST_APP}"

if [[ "${OPEN_APP}" -eq 1 ]]; then
    open "${DEST_APP}"
fi

printf 'Installed %s\n' "${DEST_APP}"
