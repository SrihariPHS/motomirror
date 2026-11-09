#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

ATTEMPTS="${1:-5}"
DELAY="${2:-30}"

if ! [[ "${ATTEMPTS}" =~ ^[0-9]+$ ]]; then
    printf 'error: attempts must be a non-negative integer\n' >&2
    exit 2
fi
if ! [[ "${DELAY}" =~ ^[0-9]+$ ]]; then
    printf 'error: delay must be a non-negative integer\n' >&2
    exit 2
fi

cd "${ROOT_DIR}"

run_gate() {
    ./scripts/verify.sh --live --target moto --wait-for-device 120
}

if [[ "${ATTEMPTS}" == "0" ]]; then
    printf 'Continuous physical gate: retrying every %s seconds until it passes.\n' "${DELAY}"
    while true; do
        if run_gate; then
            printf 'Physical gate passed.\n'
            exit 0
        fi
        printf 'Gate failed; retrying in %s seconds.\n' "${DELAY}"
        sleep "${DELAY}"
    done
fi

for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    printf '=== physical gate attempt %s/%s ===\n' "${attempt}" "${ATTEMPTS}"
    if run_gate; then
        printf 'Physical gate passed.\n'
        exit 0
    fi
    if ((attempt < ATTEMPTS)); then
        printf 'Gate failed; retrying in %s seconds.\n' "${DELAY}"
        sleep "${DELAY}"
    fi
done

printf 'Physical gate did not pass after %s attempts.\n' "${ATTEMPTS}" >&2
exit 1
