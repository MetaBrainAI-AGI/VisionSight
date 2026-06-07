#!/usr/bin/env bash
# vision-sight installer (Linux/macOS) — VisionPRIME family · MetaBrain AI.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"; command -v "$PY" >/dev/null 2>&1 || PY=python
"$PY" -c 'import sys; sys.exit(0 if sys.version_info>=(3,9) else 1)' || { echo "[X] Python 3.9+ required"; exit 1; }
echo "=== vision-sight installer ==="
echo "[*] Python: $("$PY" -V 2>&1)"
[ -f "$DIR/requirements.txt" ] && { echo "[*] dependencies..."; "$PY" -m pip install -q -r "$DIR/requirements.txt"; }
# --- Step: VisionRustify environment audit (rust-only equivalents) ---
echo "[*] VisionRustify: scanning for rust-only package replacements..."
bash "$DIR/rustify-packages.sh"  || true
# --- Step: register this product's Vision skill(s) with the harness ---
bash "$DIR/register-skills.sh" || true
echo "[OK] vision-sight installed. (run ./rustify-packages.sh --apply to swap in Rust drop-ins)"

# === VisionRustify env-audit (auto-added) ===
__rp="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rustify-packages.sh"
if [ -f "$__rp" ]; then bash "$__rp" || true; fi
