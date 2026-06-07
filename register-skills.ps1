# register-skills.ps1 — register THIS product's Vision skill(s) with the Claude Code harness.
# Copies every SKILL.md in this repo into $HOME\.claude\skills\<name>\ so the harness
# auto-discovers + loads them. Idempotent. VisionPRIME family · MetaBrain AI.
$ErrorActionPreference = 'Stop'
$Dest = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME '.claude\skills' }
$Root = $PSScriptRoot
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$n = 0
Get-ChildItem -Path $Root -Recurse -Filter SKILL.md -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\\.git\\' } | ForEach-Object {
    $line = Select-String -Path $_.FullName -Pattern '^name:\s*(.+)$' | Select-Object -First 1
    $name = if ($line) { $line.Matches[0].Groups[1].Value.Trim() } else { Split-Path $_.Directory -Leaf }
    $target = Join-Path $Dest $name
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Recurse -Force -Path (Join-Path $_.Directory '*') -Destination $target
    Write-Host "  [skill] registered: $name"
    $n++
  }
if ($n -eq 0) { Write-Host "[register-skills] no SKILL.md in this repo (nothing to register)" }
else { Write-Host "[register-skills] $n skill(s) registered into $Dest (restart your session to load)" }
