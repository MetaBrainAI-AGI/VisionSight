#!/usr/bin/env bash
# vision-sight DEV (internal) (Linux/macOS) — VisionPRIME family · MetaBrain AI.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"; command -v "$PY" >/dev/null 2>&1 || PY=python
"$PY" -c 'import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)' || { echo "[X] Python 3.9+ required"; exit 1; }
echo "=== vision-sight DEV (internal) ==="
echo "[*] Python: $("$PY" -V 2>&1)"
[ -f "$DIR/requirements.txt" ] && { echo "[*] dependencies..."; "$PY" -m pip install -q -r "$DIR/requirements.txt"; }
[ -f "$DIR/setup.py" ] || [ -f "$DIR/pyproject.toml" ] && "$PY" -m pip install -e "$DIR" >/dev/null 2>&1 || true
# --- Step: VisionRustify environment audit (rust-only equivalents) ---
echo "[*] VisionRustify: scanning for rust-only package replacements..."
bash "$DIR/rustify-packages.sh" --apply || true
# --- Step: register this product's Vision skill(s) with the harness ---
bash "$DIR/register-skills.sh" || true
echo "[OK] vision-sight installed."
