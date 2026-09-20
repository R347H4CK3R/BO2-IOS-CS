#!/usr/bin/env python3
import argparse, hashlib, json, struct
from pathlib import Path
from fastfile import parse_fastfile_header
from ipak import IPakFile

SIGNATURES = {
    b"\x89PNG": ("png", "texture"),
    b"DDS ": ("dds", "texture"),
    b"OggS": ("ogg", "audio"),
    b"RIFF": ("riff", "audio"),
    b"\x7fELF": ("elf", "executable"),
}

def detect(path: Path):
    head = path.read_bytes()[:16]
    for sig, result in SIGNATURES.items():
        if head.startswith(sig):
            return result
    ext = path.suffix.lower()
    if ext == ".ff": return "bo2_fastfile", "container"
    if ext == ".ipak": return "bo2_ipak", "texture_container"
    if ext in {".bsp", ".map"}: return ext[1:], "map"
    if ext in {".wav", ".mp3", ".at3", ".at9"}: return ext[1:], "audio"
    if ext in {".png", ".dds", ".tga", ".jpg", ".jpeg"}: return ext[1:], "texture"
    if ext in {".obj", ".mdl", ".mesh"}: return ext[1:], "mesh"
    if ext in {".json", ".cfg", ".txt", ".gsc"}: return ext[1:], "script"
    return "unknown", "unknown"

def endian_probe(path: Path):
    data = path.read_bytes()[:4]
    if len(data) < 4: return None
    return {"u32_be": struct.unpack(">I", data)[0], "u32_le": struct.unpack("<I", data)[0]}

def scan(source: Path, output: Path):
    rows = []
    output.mkdir(parents=True, exist_ok=True)
    for p in sorted(source.rglob("*")):
        if not p.is_file():
            continue
        try:
            fmt, cls = detect(p)
            row = {
                "original_path": str(p.relative_to(source)),
                "file_size": p.stat().st_size,
                "detected_format": fmt,
                "probable_asset_class": cls,
                "compression": "unknown",
                "endianness": endian_probe(p),
                "conversion_status": "discovered" if fmt != "unknown" else "unsupported",
                "converter_used": None,
                "generated_output_path": None,
                "sha256_prefix": hashlib.sha256(p.read_bytes()).hexdigest()[:16],
                "warnings": [] if fmt != "unknown" else ["Unknown format preserved for diagnostics"],
                "errors": []
            }
            if fmt == "bo2_ipak":
                try:
                    ipak = IPakFile(p)
                    inv = ipak.inventory()
                    row["ipak"] = inv
                    row["endianness"] = "big"
                    row["compression"] = "mixed LZO/uncompressed block commands"
                    row["conversion_status"] = "indexed"
                    row["converter_used"] = "ipak.py"
                    row["warnings"] = [
                        "IPAK image records are identified by hashes rather than source filenames.",
                        "Texture payload decoding/export is a later conversion stage."
                    ]
                except Exception as exc:
                    row["conversion_status"] = "header_parse_error"
                    row["errors"].append(str(exc))

            if fmt == "bo2_fastfile":
                try:
                    header = parse_fastfile_header(p)
                    row["fastfile_header"] = header.to_dict()
                    row["endianness"] = "big"
                    row["compression"] = "encrypted/compressed payload"
                    row["conversion_status"] = "encrypted_requires_decrypted_input"
                    row["warnings"] = [
                        "Authenticated BO2 PS3 fastfile detected.",
                        "Encrypted payload is not decrypted by this project; provide a legally obtained decrypted/normalized source for payload conversion."
                    ]
                except Exception as exc:
                    row["conversion_status"] = "header_parse_error"
                    row["errors"].append(str(exc))
            rows.append(row)
        except Exception as exc:
            rows.append({"original_path": str(p), "conversion_status": "error", "errors": [str(exc)]})
    inventory = {"source": str(source), "files": rows, "counts": {"total": len(rows)}}
    (output / "asset_inventory.json").write_text(json.dumps(inventory, indent=2))
    intermediate = output / "GameDataIntermediate"
    intermediate.mkdir(exist_ok=True)
    (intermediate / "schema.json").write_text(json.dumps({
        "types": ["Mesh","Material","Texture","Skeleton","Animation","Audio","Map","Entity","CollisionMesh","SpawnPoint","WeaponAsset"]
    }, indent=2))
    return inventory

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    source, output = Path(args.source).expanduser().resolve(), Path(args.output).expanduser().resolve()
    if not source.is_dir():
        raise SystemExit(f"source directory not found: {source}")
    inventory = scan(source, output)
    print(json.dumps({"status": "ok", "files": inventory["counts"]["total"]}))

if __name__ == "__main__":
    main()
