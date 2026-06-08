# VisionSight DEV (internal) (Windows) — VisionPRIME family · MetaBrain AI.
$ErrorActionPreference = 'Stop'
$DIR = $PSScriptRoot
$py = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'python3' }
& $py -c 'import sys; sys.exit(0 if sys.version_info -ge (3,9) else 1)'; if ($LASTEXITCODE) { Write-Error 'Python 3.9+ required'; exit 1 }
Write-Host "=== VisionSight DEV (internal) ==="
if (Test-Path (Join-Path $DIR 'requirements.txt')) { & $py -m pip install -q -r (Join-Path $DIR 'requirements.txt') }
if ((Test-Path (Join-Path $DIR 'setup.py')) -or (Test-Path (Join-Path $DIR 'pyproject.toml'))) { & $py -m pip install -e $DIR 2>$null }
# --- Step: VisionRustify environment audit (rust-only equivalents) ---
& (Join-Path $DIR 'rustify-packages.ps1') '--apply'
# --- Step: register this product's Vision skill(s) with the harness ---
& (Join-Path $DIR 'register-skills.ps1')
Write-Host "[OK] VisionSight installed."
