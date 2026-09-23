#!/usr/bin/env python3
"""Validate generated runtime data before packaging."""
import argparse, hashlib, json
from pathlib import Path
def h(p):
    x=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda:f.read(8*1024*1024),b""): x.update(b)
    return x.hexdigest()
def main():
    a=argparse.ArgumentParser(); a.add_argument("--root",required=True); ns=a.parse_args()
    root=Path(ns.root).resolve(); gd=root/"GeneratedGameData"
    if not gd.is_dir(): raise SystemExit("GeneratedGameData missing")
    files=[p for p in gd.rglob("*") if p.is_file()]
    rows=[{"path":p.relative_to(gd).as_posix(),"bytes":p.stat().st_size,"sha256":h(p)} for p in sorted(files)]
    out={"schema":"bo2ioscs-generated-validation-v1","file_count":len(rows),"total_bytes":sum(x["bytes"] for x in rows),"files":rows}
    (root/"GENERATED_VALIDATION.json").write_text(json.dumps(out,indent=2)+"\n")
    print(json.dumps({"status":"ok","file_count":len(rows),"total_bytes":out["total_bytes"]}))
if __name__=="__main__": main()
