#!/usr/bin/env python3
"""Private import of already-decrypted/structurally-readable user-owned assets.

This tool never decrypts BO2 fastfiles, extracts keys, or bypasses protection.
It rejects authenticated/encrypted TAff0100 fastfiles and only forwards readable
inputs to the repository's existing converter. Source files remain outside Git.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

READABLE_EXTENSIONS = {
    ".wav", ".ogg", ".png", ".dds", ".tga", ".jpg", ".jpeg",
    ".obj", ".json", ".cfg", ".txt", ".gsc", ".bsp", ".map",
    ".mdl", ".mesh", ".mp3", ".at3", ".at9", ".ipak",
}
ENCRYPTED_MAGIC = b"TAff0100"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for block in iter(lambda: fp.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def inspect_source(source: Path) -> tuple[list[dict], list[str]]:
    records: list[dict] = []
    blocked: list[str] = []
    for path in sorted(p for p in source.rglob("*") if p.is_file()):
        rel = path.relative_to(source).as_posix()
        with path.open("rb") as fp:
            head = fp.read(8)
        encrypted = head == ENCRYPTED_MAGIC
        if encrypted:
            blocked.append(rel)
        records.append({
            "path": rel,
            "size": path.stat().st_size,
            "sha256": sha256(path),
            "extension": path.suffix.lower(),
            "encrypted_fastfile": encrypted,
            "eligible_readable_input": (not encrypted and path.suffix.lower() in READABLE_EXTENSIONS),
        })
    return records, blocked


def main() -> int:
    ap = argparse.ArgumentParser(description="Import private, already-readable assets into GeneratedGameData")
    ap.add_argument("--source", required=True, help="Private directory containing legally decrypted/normalized/readable assets")
    ap.add_argument("--output", default="GeneratedGameData", help="Generated runtime output directory")
    ap.add_argument("--clean", action="store_true", help="Replace the previous generated output")
    ap.add_argument("--extract-ipak", action="store_true", help="Allow existing converter to index/extract readable IPAK data")
    ap.add_argument("--texture-metadata", help="Authoritative texture metadata JSON when generating runtime textures")
    ap.add_argument("--generate-runtime-textures", action="store_true")
    ap.add_argument("--skip-encrypted-fastfiles", action="store_true", help="Record and exclude authenticated/encrypted fastfiles instead of aborting readable-asset conversion")
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[2]
    source = Path(args.source).expanduser().resolve()
    output = (root / args.output).resolve() if not Path(args.output).is_absolute() else Path(args.output).resolve()

    if not source.is_dir():
        raise SystemExit(f"source directory not found: {source}")
    if source == root or root in source.parents:
        print("warning: private source is inside the repository; ensure it remains ignored and uncommitted", file=sys.stderr)

    records, blocked = inspect_source(source)
    if blocked and not args.skip_encrypted_fastfiles:
        print("Refusing encrypted/authenticated BO2 fastfiles:", file=sys.stderr)
        for rel in blocked:
            print(f"  - {rel}", file=sys.stderr)
        print("Provide legally decrypted/normalized or otherwise structurally readable inputs instead.", file=sys.stderr)
        return 3

    if args.clean and output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)

    manifest = {
        "schema": "bo2ioscs-private-import-v1",
        "source_root_recorded": source.name,
        "source_file_count": len(records),
        "files": records,
        "contains_encrypted_fastfiles": bool(blocked),
        "encrypted_fastfiles_excluded": len(blocked),
        "source_files_committed": False,
    }
    (output / "PRIVATE_IMPORT_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")

    converter = root / "Tools" / "PS3AssetConverter" / "convert_assets.py"
    cmd = [
        sys.executable, str(converter),
        "--source", str(source),
        "--output", str(output),
        "--import-readable-assets",
    ]
    if args.extract_ipak:
        cmd.append("--extract-ipak")
    if args.texture_metadata:
        cmd += ["--texture-metadata", str(Path(args.texture_metadata).expanduser().resolve())]
    if args.generate_runtime_textures:
        cmd.append("--generate-runtime-textures")

    subprocess.run(cmd, cwd=root, check=True)

    build_manifest = {
        "schema": "bo2ioscs-generated-gamedata-v1",
        "generated_directory": "GeneratedGameData",
        "private_source_embedded": False,
        "generated_outputs_ready_for_packaging": True,\n        "encrypted_fastfiles_excluded": len(blocked),
        "input_manifest": "PRIVATE_IMPORT_MANIFEST.json",
    }
    (output / "BUILD_MANIFEST.json").write_text(json.dumps(build_manifest, indent=2) + "\n")
    print(json.dumps({"status": "ok", "output": str(output), "files_scanned": len(records)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
