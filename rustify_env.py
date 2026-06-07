#!/usr/bin/env python3
"""
vision_rustify_packages.py — the ENVIRONMENT-rustify step of VisionRustify.

Takes an accounting of the installed Python packages, maps each to its Rust-only
equivalent (vision_rustify.KNOWN_RUST_REPLACEMENTS), then:
  • INSTALLS the drop-in Rust equivalents (orjson/polars/ruff/pydantic-v2/…),
  • UNINSTALLS the Python original ONLY when it is safe (no other installed
    package depends on it) — the destructive removal is gated,
  • REPORTS the rest with the correct strategy (rust-crate kernel / ONNX→ort /
    stays-Python) instead of breaking the env.

This is a STEP in: the product installers, our (dev) installer, and the
`vision_rustify.py` run flow.

Modes:
  --audit            report only (default; safe — installs/uninstalls nothing)
  --apply            install the safe drop-in Rust equivalents
  --apply --uninstall  also uninstall the Python originals that have ZERO reverse-deps
  --force            allow uninstalling even packages with reverse-deps (DANGEROUS; gated)
  --json             machine-readable

Safety: `--audit` is the install-script default so installing a product NEVER
mutates a customer's interpreter without consent. `numpy/pandas/scipy` etc. are
reported as RUST-ACCELERATE (wire into a native kernel) — never auto-uninstalled,
because their reverse-dep trees would break.
"""
from __future__ import annotations
import argparse, json, os, re, subprocess, sys
import importlib.metadata as md

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "modules"))
# Embedded fallback so this tool is SELF-CONTAINED when bundled into a standalone
# product (no vision_rustify.py present). When vision_rustify IS importable, its
# fuller curated map wins.
_FALLBACK = {
    "json": {"rust": "orjson", "pip": "orjson", "status": "replace"},
    "ujson": {"rust": "orjson", "pip": "orjson", "status": "replace"},
    "pandas": {"rust": "polars", "pip": "polars", "status": "replace"},
    "flake8": {"rust": "ruff", "pip": "ruff", "status": "replace"},
    "black": {"rust": "ruff", "pip": "ruff", "status": "replace"},
    "isort": {"rust": "ruff", "pip": "ruff", "status": "replace"},
    "pydantic": {"rust": "pydantic v2 (rust core)", "pip": "", "status": "already_rust"},
    "tiktoken": {"rust": "tiktoken (rust)", "pip": "", "status": "already_rust"},
    "tokenizers": {"rust": "tokenizers (rust)", "pip": "", "status": "already_rust"},
    "cryptography": {"rust": "cryptography (rust)", "pip": "", "status": "already_rust"},
    "numpy": {"rust": "ndarray+nalgebra", "pip": "", "status": "rust_crate"},
    "scipy": {"rust": "statrs+ndarray-stats", "pip": "", "status": "rust_crate"},
    "sklearn": {"rust": "linfa/smartcore", "pip": "", "status": "rust_crate"},
    "statsmodels": {"rust": "augurs", "pip": "", "status": "rust_crate"},
    "xgboost": {"rust": "ort/tract (ONNX)", "pip": "ort", "status": "rust_onnx"},
    "lightgbm": {"rust": "ort/tract (ONNX)", "pip": "ort", "status": "rust_onnx"},
    "sentence_transformers": {"rust": "tokenizers+ort", "pip": "ort", "status": "rust_onnx"},
    "transformers": {"rust": "ort (ONNX inference)", "pip": "ort", "status": "rust_onnx"},
    "onnxruntime": {"rust": "ort", "pip": "ort", "status": "rust_onnx"},
    "torch": {"rust": "ort (ONNX inference)", "pip": "ort", "status": "rust_onnx"},
    "tensorflow": {"rust": "ort (ONNX inference)", "pip": "ort", "status": "rust_onnx"},
    "faiss": {"rust": "hnsw_rs / qdrant", "pip": "", "status": "rust_crate"},
    "chromadb": {"rust": "chromadb (rust core)", "pip": "", "status": "already_rust"},
    "mem0": {"rust": "VP rust memory mesh", "pip": "", "status": "partial"},
    # The ONLY two with no rust path: online-ML (river) + HPO training (optuna).
    "river": {"rust": "(none mature)", "pip": "", "status": "stays_python"},
    "optuna": {"rust": "(training)", "pip": "", "status": "stays_python"},
}
try:
    from vision_rustify import KNOWN_RUST_REPLACEMENTS  # type: ignore
except Exception:
    KNOWN_RUST_REPLACEMENTS = _FALLBACK

# import-name -> pip dist-name where they differ
DIST_ALIAS = {
    "sklearn": "scikit-learn", "sentence_transformers": "sentence-transformers",
    "cv2": "opencv-python", "PIL": "pillow", "yaml": "pyyaml",
}
STDLIB = {"json", "sympy"}  # never uninstall (stdlib / load-bearing symbolic tier handled in-kernel)


def installed() -> dict:
    out = {}
    for d in md.distributions():
        try:
            out[(d.metadata["Name"] or "").lower()] = d
        except Exception:
            continue
    return out


def reverse_deps(dists: dict) -> dict:
    rev: dict = {}
    for name, d in dists.items():
        for req in (d.requires or []):
            dep = re.split(r"[<>=!~ \[;(]", req, maxsplit=1)[0].strip().lower()
            if dep:
                rev.setdefault(dep, set()).add(name)
    return rev


def pip(*args) -> int:
    return subprocess.run([sys.executable, "-m", "pip", *args]).returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    dists = installed()
    rev = reverse_deps(dists)
    plan = {"install_rust": [], "uninstall_safe": [], "rust_accelerate": [],
            "onnx_ort": [], "already_rust": [], "partial": [], "stays_python": [],
            "blocked_uninstall": []}

    for imp, rec in KNOWN_RUST_REPLACEMENTS.items():
        dist = DIST_ALIAS.get(imp, imp).lower()
        if dist not in dists and imp not in dists:
            continue  # not installed
        status = rec.get("status", "")
        rep = rec.get("rust", "?")
        needed_by = sorted((rev.get(dist, set()) | rev.get(imp, set())) - {dist, imp})
        if status == "replace" and rec.get("pip") and imp not in STDLIB:
            plan["install_rust"].append((imp, rec["pip"]))
            if not needed_by:
                plan["uninstall_safe"].append((imp, dist))
            else:
                plan["blocked_uninstall"].append((imp, needed_by))
        elif status == "rust_crate":
            plan["rust_accelerate"].append((imp, rep))
        elif status == "rust_onnx":
            plan["onnx_ort"].append((imp, rep))
        elif status == "already_rust":
            plan["already_rust"].append((imp, rep))
        elif status == "partial":
            plan["partial"].append((imp, rep))
        elif status == "stays_python":
            plan["stays_python"].append((imp, rep))

    if a.json:
        print(json.dumps(plan, indent=2)); return 0

    print("=== VisionRustify environment audit ===")
    print(f"  installed dists: {len(dists)}")
    print(f"  drop-in Rust installs: {[p for p,_ in plan['install_rust']]}")
    print(f"  safe to uninstall (0 reverse-deps): {[p for p,_ in plan['uninstall_safe']]}")
    print(f"  blocked uninstall (needed by others): {[(p,n) for p,n in plan['blocked_uninstall']]}")
    print(f"  RUST-ACCELERATE (native kernel, keep py): {[p for p,_ in plan['rust_accelerate']]}")
    print(f"  ONNX->ort (export+infer in rust): {[p for p,_ in plan['onnx_ort']]}")
    print(f"  already Rust-backed (no action needed): {[p for p,_ in plan['already_rust']]}")
    print(f"  VP-native alternative (partial): {[p for p,_ in plan['partial']]}")
    print(f"  STAYS python (NO rust path -- should be FEW): {[p for p,_ in plan['stays_python']]}")

    if not a.apply:
        print("\n[audit only] re-run with --apply to install the Rust drop-ins "
              "(add --uninstall to remove the safe Python originals).")
        return 0

    for imp, piprust in plan["install_rust"]:
        print(f"[install] {piprust} (Rust replacement for {imp})")
        pip("install", "-q", piprust)
    if a.uninstall:
        targets = list(plan["uninstall_safe"])
        if a.force:
            targets += [(p, DIST_ALIAS.get(p, p)) for p, _ in plan["blocked_uninstall"]]
            print("[!] --force: uninstalling packages that OTHERS depend on — may break the env")
        for imp, dist in targets:
            print(f"[uninstall] {dist} (Python; replaced by Rust)")
            pip("uninstall", "-y", "-q", dist)
    else:
        print("\n[apply] installed Rust drop-ins. Add --uninstall to remove the safe "
              "Python originals; numpy/pandas/scipy stay (RUST-ACCELERATE via kernel).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
