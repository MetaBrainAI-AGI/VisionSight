# rustify-packages.ps1 — audit installed Python packages -> rust-only equivalents.
# Default is a SAFE audit; add --apply (and --uninstall) to swap. VisionPRIME · MetaBrain AI.
$py = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'python3' }
& $py (Join-Path $PSScriptRoot 'rustify_env.py') @args
