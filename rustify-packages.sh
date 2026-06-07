#!/usr/bin/env bash
# rustify-packages.sh — audit installed Python packages, find rust-only equivalents,
# install the drop-ins, and (with --apply --uninstall) remove the safe Python originals.
# Default is a SAFE audit (changes nothing). VisionPRIME family · MetaBrain AI.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"; command -v "$PY" >/dev/null 2>&1 || PY=python
"$PY" "$DIR/rustify_env.py" "$@"
