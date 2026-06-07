#!/usr/bin/env bash
# vision_sight_install.sh -- VisionPRIME SIGHT prereq installer (the "eyes").
#
# Installs + verifies the prerequisites for VisionPRIME's two eyes:
#   * mss         -- screen capture (MIT, PERMISSIVE -> used as-is, not recreated)
#   * pillow      -- screen-capture fallback (PIL.ImageGrab) + image dims
#   * playwright  -- headless browser (Apache-2.0) + its Chromium build (BSD)
#   * requests    -- the vision-LLM HTTP call (Apache-2.0)
#   * opencv-python -- camera presence eye (Apache-2.0; OPT-IN feature camera_presence)
#
# All four are PERMISSIVE OSS -> no license issue, no recreation. The vision
# model itself is reached over its HTTP API with the operator's own vault keys
# (GEMINI/GOOGLE_AI_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY) -- nothing to
# install for that.
#
# Behavior per package: CHECK installed -> CHECK latest (PyPI) -> PROMPT to
# upgrade (yes=upgrade / no=skip). Non-interactive (CI / VP_NONINTERACTIVE) is
# SAFE: it installs anything MISSING but never blocks on a prompt, and prints an
# ACTION-NEEDED line for any upgrade it skipped.
#
# Usage:
#   bash ~/.claude/vision_self/scripts/vision_sight_install.sh            # install + verify
#   bash ~/.claude/vision_self/scripts/vision_sight_install.sh --verify   # verify only
#   VP_NONINTERACTIVE=1 bash ...vision_sight_install.sh                   # CI / unattended
#
# Multi-OS: detects Windows-Python / Linux / macOS, picks the absolute
# interpreter, NEVER uses bare `python` (MS Store stub on Windows).
set -uo pipefail

# ---- absolute python (NEVER bare python -- MS Store stub) ------------------
PY_WIN="C:/Users/user/AppData/Local/Programs/Python/Python313/python.exe"
if [ -n "${VISION_SIGHT_PYTHON:-}" ] && [ -x "${VISION_SIGHT_PYTHON}" ]; then
  PY="${VISION_SIGHT_PYTHON}"
elif [ -x "$PY_WIN" ]; then
  PY="$PY_WIN"
elif command -v python3 >/dev/null 2>&1; then
  PY="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PY="$(command -v python)"
else
  echo "[vision-sight] FATAL: no python interpreter found." >&2
  exit 3
fi
echo "[vision-sight] python = $PY"
"$PY" --version || true

VERIFY_ONLY=0
[ "${1:-}" = "--verify" ] && VERIFY_ONLY=1

# Non-interactive if asked, or if there is no TTY (CI).
NONINTERACTIVE=0
if [ "${VP_NONINTERACTIVE:-0}" = "1" ] || [ "${CI:-}" = "true" ] || [ ! -t 0 ]; then
  NONINTERACTIVE=1
fi

ACTION_NEEDED=()

# pkg_installed <import_name> -> 0 if importable
pkg_installed() { "$PY" -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('$1') else 1)" 2>/dev/null; }

# installed_version <dist_name>
installed_version() { "$PY" -c "import importlib.metadata as m; print(m.version('$1'))" 2>/dev/null || echo ""; }

# latest_version <dist_name> (best-effort via pip index; empty if offline)
latest_version() {
  "$PY" -m pip index versions "$1" 2>/dev/null \
    | sed -n 's/.*Available versions: \([^,]*\).*/\1/p' | head -n1 | tr -d ' '
}

# ensure_pkg <dist_name> <import_name>
#   CHECK installed -> CHECK latest -> PROMPT upgrade (interactive) / install-if-missing.
ensure_pkg() {
  local dist="$1" imp="$2"
  if pkg_installed "$imp"; then
    local cur latest; cur="$(installed_version "$dist")"; latest="$(latest_version "$dist")"
    if [ -n "$latest" ] && [ -n "$cur" ] && [ "$cur" != "$latest" ]; then
      if [ "$VERIFY_ONLY" = "1" ]; then
        echo "[vision-sight] $dist $cur installed (latest $latest) -- verify-only, not upgrading"
      elif [ "$NONINTERACTIVE" = "1" ]; then
        echo "[vision-sight] $dist $cur installed; latest is $latest (non-interactive: SKIP upgrade)"
        ACTION_NEEDED+=("upgrade $dist: $PY -m pip install -U $dist  ($cur -> $latest)")
      else
        printf "[vision-sight] %s %s installed; upgrade to %s? [y/N] " "$dist" "$cur" "$latest"
        read -r ans
        case "$ans" in
          y|Y|yes|YES) "$PY" -m pip install -U "$dist" && echo "[vision-sight] upgraded $dist";;
          *) echo "[vision-sight] kept $dist $cur";;
        esac
      fi
    else
      echo "[vision-sight] $dist OK ($cur)"
    fi
  else
    if [ "$VERIFY_ONLY" = "1" ]; then
      echo "[vision-sight] $dist MISSING (verify-only, not installing)"
      ACTION_NEEDED+=("install $dist: $PY -m pip install $dist")
    else
      echo "[vision-sight] installing $dist ..."
      "$PY" -m pip install "$dist" && echo "[vision-sight] installed $dist" \
        || { echo "[vision-sight] WARN: failed to install $dist"; ACTION_NEEDED+=("install $dist (failed): $PY -m pip install $dist"); }
    fi
  fi
}

echo "=== VisionPRIME SIGHT installer (eyes: screen + headless browser + vision) ==="
ensure_pkg "mss" "mss"
ensure_pkg "pillow" "PIL"
ensure_pkg "requests" "requests"
ensure_pkg "playwright" "playwright"
ensure_pkg "opencv-python" "cv2"   # camera presence eye (opt-in feature camera_presence)

# ---- Playwright Chromium build --------------------------------------------
chromium_present() {
  "$PY" - <<'PYEOF' 2>/dev/null
import os, sys
try:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        exe = p.chromium.executable_path
    sys.exit(0 if (exe and os.path.exists(exe)) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

if pkg_installed "playwright"; then
  if chromium_present; then
    echo "[vision-sight] Playwright Chromium OK"
  else
    if [ "$VERIFY_ONLY" = "1" ]; then
      echo "[vision-sight] Playwright Chromium MISSING (verify-only)"
      ACTION_NEEDED+=("install chromium: $PY -m playwright install chromium")
    else
      echo "[vision-sight] installing Playwright Chromium (headless browser engine) ..."
      "$PY" -m playwright install chromium \
        && echo "[vision-sight] Chromium installed" \
        || { echo "[vision-sight] WARN: chromium install failed"; ACTION_NEEDED+=("install chromium (failed): $PY -m playwright install chromium"); }
    fi
  fi
fi

# ---- verify the modules import + report readiness -------------------------
echo "=== verify: importing the eyes ==="
MODDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../modules" && pwd 2>/dev/null || echo "${HOME}/.claude/vision_self/modules")"
VISION_SELF_DIR="${VISION_SELF_DIR:-${HOME}/.claude/vision_self}" \
"$PY" - "$MODDIR" <<'PYEOF'
import sys, json
sys.path.insert(0, sys.argv[1])
ok = True
try:
    import vision_screen, vision_browser, vision_sight
    s = vision_sight.status()
    print("[vision-sight] screen ready:", s["screen"].get("ready"),
          "| browser ready:", s["browser"].get("ready"),
          "| can_see:", s["can_see"])
    print("[vision-sight] vision models reachable:", s["vision_models_available"] or "(none -- add a vault key)")
    try:
        import vision_camera, vision_presence
        print("[vision-sight] camera eye: cv2=%s enabled(opt-in)=%s | presence idle=%ss" % (
            vision_camera.cv2_available(), vision_camera.enabled(), vision_presence.idle_seconds()))
    except Exception as _e:
        print("[vision-sight] camera/presence not wired:", type(_e).__name__, _e)
    print("[vision-sight] STATUS:", json.dumps(s, default=str)[:400])
except Exception as exc:
    ok = False
    print("[vision-sight] IMPORT/VERIFY FAILED:", type(exc).__name__, exc)
sys.exit(0 if ok else 4)
PYEOF
RC=$?

if [ "${#ACTION_NEEDED[@]}" -gt 0 ]; then
  echo ""
  echo "=== ACTION-NEEDED (run these to finish) ==="
  for a in "${ACTION_NEEDED[@]}"; do echo "  - $a"; done
fi

if [ "$RC" -eq 0 ]; then
  echo "[vision-sight] DONE -- VisionPRIME's eyes are wired."
else
  echo "[vision-sight] DONE with warnings (see ACTION-NEEDED above)."
fi
exit "$RC"
