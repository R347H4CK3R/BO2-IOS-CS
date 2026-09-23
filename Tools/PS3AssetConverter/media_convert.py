#!/usr/bin/env python3
"""Convert structurally readable media into iOS runtime formats.

This intentionally does not decrypt or bypass authenticated BO2 containers.
It converts only files ffmpeg can already decode.
"""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path

VIDEO_EXTS={".bik",".avi",".mp4",".m4v",".mov"}
AUDIO_EXTS={".wav",".ogg",".mp3",".flac",".m4a",".aac"}

def sha256(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda:f.read(8*1024*1024),b""): h.update(block)
    return h.hexdigest()

def ffmpeg():
    exe=shutil.which("ffmpeg")
    if not exe: raise SystemExit("ffmpeg is required (brew install ffmpeg / apt install ffmpeg)")
    return exe

def convert(source, output):
    exe=ffmpeg(); root=output/"GeneratedGameData"/"Media"; root.mkdir(parents=True,exist_ok=True)
    records=[]
    for p in sorted(source.rglob("*")):
        if not p.is_file(): continue
        ext=p.suffix.lower()
        if ext not in VIDEO_EXTS|AUDIO_EXTS: continue
        rel=p.relative_to(source)
        if ext in VIDEO_EXTS:
            dst=(root/"Video"/rel).with_suffix(".mp4")
            cmd=[exe,"-nostdin","-hide_banner","-loglevel","error","-y","-i",str(p),
                 "-map","0:v:0?","-map","0:a:0?","-c:v","h264","-pix_fmt","yuv420p",
                 "-movflags","+faststart","-c:a","aac","-b:a","160k",str(dst)]
            kind="video"
        else:
            dst=(root/"Audio"/rel).with_suffix(".m4a")
            cmd=[exe,"-nostdin","-hide_banner","-loglevel","error","-y","-i",str(p),
                 "-vn","-c:a","aac","-b:a","160k",str(dst)]
            kind="audio"
        dst.parent.mkdir(parents=True,exist_ok=True)
        try:
            subprocess.run(cmd,check=True)
            records.append({"source":str(rel),"kind":kind,"output":str(dst.relative_to(output)),
                            "source_sha256":sha256(p),"output_sha256":sha256(dst),
                            "output_bytes":dst.stat().st_size,"status":"converted"})
        except subprocess.CalledProcessError as e:
            dst.unlink(missing_ok=True)
            records.append({"source":str(rel),"kind":kind,"status":"decode_failed","returncode":e.returncode})
    manifest={"schema":"bo2ioscs-runtime-media-v1","policy":"readable media only; no container decryption","records":records}
    out=output/"GeneratedGameData"/"runtime_media_manifest.json"
    out.write_text(json.dumps(manifest,indent=2)+"\n")
    return records

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--source",required=True); ap.add_argument("--output",required=True)
    a=ap.parse_args(); s=Path(a.source).expanduser().resolve(); o=Path(a.output).expanduser().resolve()
    if not s.is_dir(): raise SystemExit(f"source directory not found: {s}")
    rows=convert(s,o)
    print(json.dumps({"status":"ok","converted":sum(r["status"]=="converted" for r in rows),"failed":sum(r["status"]!="converted" for r in rows)}))
if __name__=="__main__": main()
