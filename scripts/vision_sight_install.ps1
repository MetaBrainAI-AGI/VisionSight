# vision_sight_install.ps1 -- VisionPRIME SIGHT prereq installer (the "eyes").
#
# Installs + verifies the prerequisites for VisionPRIME's two eyes:
#   * mss         -- screen capture (MIT, PERMISSIVE -> used as-is, not recreated)
#   * pillow      -- screen-capture fallback (PIL.ImageGrab) + image dims
#   * playwright  -- headless browser (Apache-2.0) + its Chromium build (BSD)
#   * requests    -- the vision-LLM HTTP call (Apache-2.0)
#   * opencv-python -- camera presence eye (Apache-2.0; OPT-IN feature camera_presence)
#
# All four are PERMISSIVE OSS -> no license issue, no recreation. The vision
# model is reached over its HTTP API with the operator's own vault keys
# (GEMINI/GOOGLE_AI_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY).
#
# Per package: CHECK installed -> CHECK latest (PyPI) -> PROMPT to upgrade
# (yes=upgrade / no=skip). Non-interactive ($env:VP_NONINTERACTIVE=1 / CI / no
# console) is SAFE: installs anything MISSING, never blocks, and prints an
# ACTION-NEEDED line for any upgrade it skipped.
#
# Usage:
#   powershell -File ~\.claude\vision_self\scripts\vision_sight_install.ps1
#   powershell -File ...\vision_sight_install.ps1 -VerifyOnly
#   $env:VP_NONINTERACTIVE=1; powershell -File ...\vision_sight_install.ps1

param([switch]$VerifyOnly)

$ErrorActionPreference = "Continue"

# ---- absolute python (NEVER bare python -- MS Store stub) ------------------
$PyWin = "<path>\AppData\Local\Programs\Python\Python313\python.exe"
if ($env:VISION_SIGHT_PYTHON -and (Test-Path $env:VISION_SIGHT_PYTHON)) {
  $PY = $env:VISION_SIGHT_PYTHON
} elseif (Test-Path $PyWin) {
  $PY = $PyWin
} else {
  $cmd = Get-Command python3 -ErrorAction SilentlyContinue
  if (-not $cmd) { $cmd = Get-Command python -ErrorAction SilentlyContinue }
  if ($cmd) { $PY = $cmd.Source } else { Write-Host "[vision-sight] FATAL: no python found." ; exit 3 }
}
Write-Host "[vision-sight] python = $PY"
& $PY --version

# Non-interactive if asked, CI, or no interactive console.
$NonInteractive = $false
if ($env:VP_NONINTERACTIVE -eq "1" -or $env:CI -eq "true" -or -not [Environment]::UserInteractive) {
  $NonInteractive = $true
}

$ActionNeeded = New-Object System.Collections.Generic.List[string]

function Pkg-Installed([string]$imp) {
  & $PY -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('$imp') else 1)" 2>$null
  return ($LASTEXITCODE -eq 0)
}
function Installed-Version([string]$dist) {
  $v = & $PY -c "import importlib.metadata as m; print(m.version('$dist'))" 2>$null
  if ($LASTEXITCODE -eq 0) { return $v.Trim() } else { return "" }
}
function Latest-Version([string]$dist) {
  $out = & $PY -m pip index versions $dist 2>$null
  if ($out -match "Available versions:\s*([^,\r\n]+)") { return $Matches[1].Trim() } else { return "" }
}

function Ensure-Pkg([string]$dist, [string]$imp) {
  if (Pkg-Installed $imp) {
    $cur = Installed-Version $dist
    $latest = Latest-Version $dist
    if ($latest -and $cur -and ($cur -ne $latest)) {
      if ($VerifyOnly) {
        Write-Host "[vision-sight] $dist $cur installed (latest $latest) -- verify-only"
      } elseif ($NonInteractive) {
        Write-Host "[vision-sight] $dist $cur installed; latest $latest (non-interactive: SKIP)"
        $ActionNeeded.Add("upgrade ${dist}: $PY -m pip install -U $dist  ($cur -> $latest)")
      } else {
        $ans = Read-Host "[vision-sight] $dist $cur installed; upgrade to $latest? [y/N]"
        if ($ans -match '^(y|yes)$') { & $PY -m pip install -U $dist; Write-Host "[vision-sight] upgraded $dist" }
        else { Write-Host "[vision-sight] kept $dist $cur" }
      }
    } else {
      Write-Host "[vision-sight] $dist OK ($cur)"
    }
  } else {
    if ($VerifyOnly) {
      Write-Host "[vision-sight] $dist MISSING (verify-only)"
      $ActionNeeded.Add("install ${dist}: $PY -m pip install $dist")
    } else {
      Write-Host "[vision-sight] installing $dist ..."
      & $PY -m pip install $dist
      if ($LASTEXITCODE -eq 0) { Write-Host "[vision-sight] installed $dist" }
      else { Write-Host "[vision-sight] WARN: failed to install $dist"; $ActionNeeded.Add("install $dist (failed): $PY -m pip install $dist") }
    }
  }
}

Write-Host "=== VisionPRIME SIGHT installer (eyes: screen + headless browser + vision) ==="
Ensure-Pkg "mss" "mss"
Ensure-Pkg "pillow" "PIL"
Ensure-Pkg "requests" "requests"
Ensure-Pkg "playwright" "playwright"
Ensure-Pkg "opencv-python" "cv2"   # camera presence eye (opt-in feature camera_presence)

# ---- Playwright Chromium build --------------------------------------------
function Chromium-Present() {
  $code = @"
import os, sys
try:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        exe = p.chromium.executable_path
    sys.exit(0 if (exe and os.path.exists(exe)) else 1)
except Exception:
    sys.exit(1)
"@
  & $PY -c $code 2>$null
  return ($LASTEXITCODE -eq 0)
}

if (Pkg-Installed "playwright") {
  if (Chromium-Present) {
    Write-Host "[vision-sight] Playwright Chromium OK"
  } else {
    if ($VerifyOnly) {
      Write-Host "[vision-sight] Playwright Chromium MISSING (verify-only)"
      $ActionNeeded.Add("install chromium: $PY -m playwright install chromium")
    } else {
      Write-Host "[vision-sight] installing Playwright Chromium (headless browser engine) ..."
      & $PY -m playwright install chromium
      if ($LASTEXITCODE -eq 0) { Write-Host "[vision-sight] Chromium installed" }
      else { Write-Host "[vision-sight] WARN: chromium install failed"; $ActionNeeded.Add("install chromium (failed): $PY -m playwright install chromium") }
    }
  }
}

# ---- verify the modules import + report readiness -------------------------
Write-Host "=== verify: importing the eyes ==="
$ModDir = Join-Path (Split-Path -Parent $PSScriptRoot) "modules"
if (-not (Test-Path $ModDir)) { $ModDir = Join-Path $HOME ".claude\vision_self\modules" }
if (-not $env:VISION_SELF_DIR) { $env:VISION_SELF_DIR = (Join-Path $HOME ".claude\vision_self") }

$verifyCode = @"
import sys, json
sys.path.insert(0, r'''$ModDir''')
try:
    import vision_screen, vision_browser, vision_sight
    s = vision_sight.status()
    print('[vision-sight] screen ready:', s['screen'].get('ready'),
          '| browser ready:', s['browser'].get('ready'),
          '| can_see:', s['can_see'])
    print('[vision-sight] vision models reachable:', s['vision_models_available'] or '(none -- add a vault key)')
    try:
        import vision_camera, vision_presence
        print('[vision-sight] camera eye: cv2=%s enabled(opt-in)=%s | presence idle=%ss' % (
            vision_camera.cv2_available(), vision_camera.enabled(), vision_presence.idle_seconds()))
    except Exception as _e:
        print('[vision-sight] camera/presence not wired:', type(_e).__name__, _e)
    print('[vision-sight] STATUS:', json.dumps(s, default=str)[:400])
    sys.exit(0)
except Exception as exc:
    print('[vision-sight] IMPORT/VERIFY FAILED:', type(exc).__name__, exc)
    sys.exit(4)
"@
& $PY -c $verifyCode
$RC = $LASTEXITCODE

if ($ActionNeeded.Count -gt 0) {
  Write-Host ""
  Write-Host "=== ACTION-NEEDED (run these to finish) ==="
  foreach ($a in $ActionNeeded) { Write-Host "  - $a" }
}

if ($RC -eq 0) { Write-Host "[vision-sight] DONE -- VisionPRIME's eyes are wired." }
else { Write-Host "[vision-sight] DONE with warnings (see ACTION-NEEDED above)." }
exit $RC
