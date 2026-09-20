#!/usr/bin/env python3
import argparse, hashlib, json, struct
from pathlib import Path
from fastfile import parse_fastfile_header
from ipak import DATA_HASH_MASK, IPakFile

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

def extract_ipak_payloads(source: Path, output: Path):
    texture_root = output / "GameDataIntermediate" / "TexturePayloads"
    texture_root.mkdir(parents=True, exist_ok=True)
    records = []

    for ipak_path in sorted(source.rglob("*.ipak")):
        try:
            ipak = IPakFile(ipak_path)
        except Exception as exc:
            records.append({
                "source": str(ipak_path.relative_to(source)),
                "status": "container_error",
                "error": str(exc),
            })
            continue

        package_dir = texture_root / ipak_path.stem
        package_dir.mkdir(parents=True, exist_ok=True)

        for index, entry in enumerate(ipak.entries):
            output_name = (
                f"{index:06d}_{entry.name_hash:08x}_"
                f"{entry.data_hash & DATA_HASH_MASK:08x}.bin"
            )
            output_path = package_dir / output_name
            try:
                payload = ipak.extract_entry(entry)
                output_path.write_bytes(payload)
                records.append({
                    "source": str(ipak_path.relative_to(source)),
                    "entry_index": index,
                    "name_hash": f"0x{entry.name_hash:08X}",
                    "data_crc": f"0x{entry.data_hash & DATA_HASH_MASK:08X}",
                    "stored_region_size": entry.size,
                    "decoded_size": len(payload),
                    "status": "decoded_payload",
                    "generated_output_path": str(output_path.relative_to(output)),
                })
            except Exception as exc:
                records.append({
                    "source": str(ipak_path.relative_to(source)),
                    "entry_index": index,
                    "name_hash": f"0x{entry.name_hash:08X}",
                    "data_crc": f"0x{entry.data_hash & DATA_HASH_MASK:08X}",
                    "stored_region_size": entry.size,
                    "status": "decode_error",
                    "error": str(exc),
                })

    report_path = output / "GameDataIntermediate" / "texture_payload_inventory.json"
    report_path.write_text(json.dumps({
        "schema": "bo2ioscs-texture-payload-inventory-v1",
        "records": records,
    }, indent=2))
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--extract-ipak",
        action="store_true",
        help="Decode IPAK image payloads into GameDataIntermediate/TexturePayloads",
    )
    args = parser.parse_args()
    source, output = Path(args.source).expanduser().resolve(), Path(args.output).expanduser().resolve()
    if not source.is_dir():
        raise SystemExit(f"source directory not found: {source}")
    inventory = scan(source, output)
    result = {"status": "ok", "files": inventory["counts"]["total"]}
    if args.extract_ipak:
        records = extract_ipak_payloads(source, output)
        result["ipak_payload_records"] = len(records)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
