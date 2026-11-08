#!/usr/bin/env python3
"""Archive tracked, exact build sources including initialized submodules and patches."""
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path


def tracked_files(root):
    names=subprocess.check_output(['git','-C',str(root),'ls-files','-z','--recurse-submodules']).decode().split('\0')
    for name in sorted(filter(None,names)):
        path=root/name
        if path.is_symlink():
            raise ValueError('Review source symlink before archiving: '+name)
        if path.is_dir():
            raise ValueError('Unexpanded submodule: '+name)
        if not path.is_file() or root.resolve() not in path.resolve().parents:
            raise ValueError('Invalid tracked source file: '+name)
        yield name,path


def archive_sources(roots, output):
    entries=[]; provenance=[]
    for label,root in roots.items():
        revision=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
        provenance.append({'component':label,'revision':revision})
        for name,path in tracked_files(root):
            data=path.read_bytes()
            entries.append((label+'/'+name,data,bool(path.stat().st_mode&0o111)))
    manifest={'repositories':provenance,'files':[{'path':name,'sha256':hashlib.sha256(data).hexdigest()} for name,data,_ in entries],
              'scope':'Exact tracked working-tree sources used in this build, including initialized submodules and applied build-script patches. No build products or Git credentials.'}
    entries.append(('SOURCE-MANIFEST.json',(json.dumps(manifest,indent=2)+'\n').encode(),False))
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name,data,executable in sorted(entries):
            info=zipfile.ZipInfo(name,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.create_system=3
            info.external_attr=((0o100755 if executable else 0o100644)<<16)
            z.writestr(info,data)
    return {'sourceFiles':len(entries)-1,'sourceBytes':output.stat().st_size,'sourceSHA256':hashlib.sha256(output.read_bytes()).hexdigest()}


if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    roots={'BO2-IOS-CS':root,**{name:root/'Build/OpenSourceEngine'/name for name in ('xash3d-fwgs','SDL2','hlsdk-portable')}}
    result=archive_sources(roots,root/'Build/XashRuntime/BO2IOSCS-Xash-source.zip')
    (root/'Build/XashRuntime/SOURCE-VERIFICATION.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
