#!/usr/bin/env bash
# MotoMirror verification wrapper.
#
# Usage:
#   scripts/verify.sh                          # static checks only
#   scripts/verify.sh --live                   # full 100-check live gate
#   scripts/verify.sh --live --target moto     # physical Moto G85 gate
#
# All arguments are forwarded to verify/verify.py. The Python process runs
# from the repository root so that verification/ and artifacts/ resolve there.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "${repo_root}"

exec python3 "verify/verify.py" "$@"
