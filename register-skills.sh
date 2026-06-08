#!/usr/bin/env bash
# register-skills.sh — register THIS product's Vision skill(s) with the Claude Code harness.
# Copies every SKILL.md in this repo into ~/.claude/skills/<name>/ so the harness
# auto-discovers + loads them on next session. Idempotent. VisionPRIME family · MetaBrain AI.
set -euo pipefail
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$DEST"
n=0
while IFS= read -r skill; do
  name="$(awk -F': *' '/^name:/{gsub(/\r/,""); print $2; exit}' "$skill")"
  [ -z "$name" ] && name="$(basename "$(dirname "$skill")")"
  mkdir -p "$DEST/$name"
  # APPEND-ONLY LESSONS STANDARD: never clobber the customer's accumulated lessons.
  # Snapshot them, let the copy land the shipped baseline, then restore + append-merge.
  for L in lessons.jsonl LESSONS.md; do
    [ -f "$DEST/$name/$L" ] && cp -f "$DEST/$name/$L" "$DEST/$name/.cust.$L" 2>/dev/null || true
  done
  cp -rf "$(dirname "$skill")/." "$DEST/$name/"
  for L in lessons.jsonl LESSONS.md; do
    [ -f "$DEST/$name/.cust.$L" ] && mv -f "$DEST/$name/.cust.$L" "$DEST/$name/$L" 2>/dev/null || true
  done
  PYB="${PYTHON:-python3}"; command -v "$PYB" >/dev/null 2>&1 || PYB=python
  [ -f "$DEST/$name/vp_lessons_merge.py" ] && "$PYB" "$DEST/$name/vp_lessons_merge.py" --dir "$DEST/$name" >/dev/null 2>&1 || true
  printf '  [skill] registered: %s (customer lessons preserved + baseline merged)\n' "$name"
  n=$((n+1))
done < <(find "$ROOT" -name SKILL.md -not -path '*/.git/*' 2>/dev/null)
if [ "$n" -eq 0 ]; then
  printf '[register-skills] no SKILL.md in this repo (nothing to register)\n'
else
  printf '[register-skills] %s skill(s) registered into %s (restart your session to load)\n' "$n" "$DEST"
fi
