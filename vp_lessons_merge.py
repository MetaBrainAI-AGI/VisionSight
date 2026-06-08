#!/usr/bin/env python3
"""
vp_lessons_merge.py — THE append-only lessons standard for VisionPRIME products.

Owner directive 2026-06-07: a product update/upgrade must NEVER overwrite the
customer's accumulated lessons. Dev lessons ship as a READ-ONLY baseline; the
customer's lessons are APPEND-ONLY and preserved forever.

File layout (per skill / product dir):
  lessons.shipped.jsonl   LESSONS.shipped.md   <- DEV/product baseline (read-only, replaced on upgrade)
  lessons.jsonl           LESSONS.md           <- CUSTOMER-accumulated (append-only, NEVER overwritten)

This tool APPENDS the shipped baseline into the customer files, de-duplicated, with
the customer's own entries preserved verbatim and FIRST. Idempotent (re-running adds
nothing). Zero-loss by construction. Stdlib-only so it runs on any customer machine.

Usage (the product installer / register-skills calls this):
  python vp_lessons_merge.py --dir <skill_or_product_dir>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def _key(rec) -> str:
    """Stable dedup key: an explicit id/hash field if present, else a sha1 of the
    canonical lesson text. Two identical lessons collapse; a customer edit stays distinct."""
    if isinstance(rec, dict):
        for k in ("id", "hash", "key", "uid"):
            v = rec.get(k)
            if v:
                return "id:" + str(v)
        core = rec.get("lesson") or rec.get("text") or rec.get("title") or json.dumps(rec, sort_keys=True, default=str)
    else:
        core = str(rec)
    return "h:" + hashlib.sha1(str(core).strip().encode("utf-8", "replace")).hexdigest()


def merge_jsonl(shipped: Path, customer: Path) -> dict:
    """Append shipped jsonl lessons the customer doesn't already have. Customer lines
    are preserved verbatim and come FIRST; new shipped lines are appended."""
    if not shipped.exists():
        return {"appended": 0, "reason": "no shipped jsonl"}
    have = set()
    cust_lines = []
    if customer.exists():
        for ln in customer.read_text(encoding="utf-8", errors="ignore").splitlines():
            ln = ln.strip()
            if not ln:
                continue
            cust_lines.append(ln)
            try:
                have.add(_key(json.loads(ln)))
            except Exception:
                have.add("raw:" + ln)
    appended = 0
    new_lines = []
    for ln in shipped.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            k = _key(json.loads(ln))
        except Exception:
            k = "raw:" + ln
        if k in have:
            continue
        have.add(k)
        new_lines.append(ln)
        appended += 1
    if appended:
        customer.write_text("\n".join(cust_lines + new_lines) + "\n", encoding="utf-8")
    return {"appended": appended, "customer_total": len(cust_lines) + appended}


def merge_md(shipped: Path, customer: Path) -> dict:
    """Append the shipped LESSONS.md block ONCE (marker-guarded by content hash) to the
    END of the customer's file. Never rewrites the customer's existing content."""
    if not shipped.exists():
        return {"appended": False, "reason": "no shipped md"}
    ship_txt = shipped.read_text(encoding="utf-8", errors="ignore").strip()
    if not ship_txt:
        return {"appended": False, "reason": "shipped md empty"}
    marker = "<!-- vp-shipped-lessons %s -->" % hashlib.sha1(ship_txt.encode("utf-8", "replace")).hexdigest()[:12]
    cust_txt = customer.read_text(encoding="utf-8", errors="ignore") if customer.exists() else ""
    if marker in cust_txt:
        return {"appended": False, "reason": "already merged"}
    block = "%s\n## Shipped lessons (product baseline)\n\n%s\n" % (marker, ship_txt)
    if cust_txt.strip():
        customer.write_text(cust_txt.rstrip() + "\n\n" + block, encoding="utf-8")
    else:
        customer.write_text(block, encoding="utf-8")
    return {"appended": True}


def run(d: Path) -> dict:
    return {
        "dir": str(d),
        "jsonl": merge_jsonl(d / "lessons.shipped.jsonl", d / "lessons.jsonl"),
        "md": merge_md(d / "LESSONS.shipped.md", d / "LESSONS.md"),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".")
    a = ap.parse_args()
    try:
        print(json.dumps(run(Path(a.dir).resolve()), default=str))
    except Exception as e:  # fail-open: a merge problem must never break an install
        print(json.dumps({"error": "%s: %s" % (type(e).__name__, e)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
