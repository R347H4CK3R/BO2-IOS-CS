#!/usr/bin/env python3
"""Strict runtime texture writer for decoded payloads with authoritative metadata.

No container decryption or metadata inference is performed. PS3 swizzled conversion
is opt-in and requires authoritative Morton-order metadata; tiled layouts remain
rejected until their exact platform layout is documented and validated.
"""
import struct
from pathlib import Path

def expected_payload_size(width, height, fmt):
    if fmt == "BC1": return ((width + 3)//4)*((height + 3)//4)*8
    if fmt in {"BC2","BC3"}: return ((width + 3)//4)*((height + 3)//4)*16
    if fmt in {"RGBA8","BGRA8"}: return width*height*4
    return None

def _part1by1(v):
    v &= 0xFFFF
    v=(v|(v<<8))&0x00FF00FF; v=(v|(v<<4))&0x0F0F0F0F
    v=(v|(v<<2))&0x33333333; v=(v|(v<<1))&0x55555555
    return v

def _morton2(x,y): return _part1by1(x)|(_part1by1(y)<<1)

def unswizzle_morton(payload,width,height,unit_bytes):
    """Convert a 2D Morton/Z-order payload to row-major units.

    Dimensions are in storage units (pixels for RGBA/BGRA, 4x4 blocks for BCn).
    Only power-of-two rectangular unit grids are accepted so padding is never guessed.
    """
    if width < 1 or height < 1 or width & (width-1) or height & (height-1):
        raise ValueError("validated Morton conversion requires power-of-two storage dimensions")
    count=width*height
    if len(payload)!=count*unit_bytes: raise ValueError("swizzled payload size mismatch")
    out=bytearray(len(payload))
    # Rectangular Morton ranks are obtained by sorting valid coordinates by Morton key.
    coords=sorted((( _morton2(x,y),x,y) for y in range(height) for x in range(width)))
    for src_index,(_,x,y) in enumerate(coords):
        dst=(y*width+x)*unit_bytes; src=src_index*unit_bytes
        out[dst:dst+unit_bytes]=payload[src:src+unit_bytes]
    return bytes(out)

def _linearize(payload, metadata):
    layout=metadata["layout"]; fmt=metadata["format"]; w=metadata["width"]; h=metadata["height"]
    if layout=="linear": return payload
    if layout!="ps3_swizzled": return None
    if metadata.get("swizzle")!="morton2d":
        raise ValueError("ps3_swizzled requires authoritative swizzle=morton2d")
    if fmt=="BC1": return unswizzle_morton(payload,(w+3)//4,(h+3)//4,8)
    if fmt in {"BC2","BC3"}: return unswizzle_morton(payload,(w+3)//4,(h+3)//4,16)
    if fmt in {"RGBA8","BGRA8"}: return unswizzle_morton(payload,w,h,4)
    raise ValueError(f"{fmt} swizzle conversion is not validated")

def _dds_header(width,height,fmt,payload_size):
    fourcc={"BC1":b"DXT1","BC2":b"DXT3","BC3":b"DXT5"}[fmt]
    header=struct.pack("<IIIIIII11I",124,0x00081007,height,width,payload_size,0,1,*([0]*11))
    pf=struct.pack("<II4sIIIII",32,0x4,fourcc,0,0,0,0,0)
    return b"DDS "+header+pf+struct.pack("<IIIII",0x1000,0,0,0,0)

def write_runtime_texture(payload,metadata,destination):
    w,h=metadata["width"],metadata["height"]; fmt=metadata["format"]
    expected=expected_payload_size(w,h,fmt)
    if expected is None: return {"status":"format_conversion_required","reason":f"{fmt} export is not validated"}
    if len(payload)!=expected: return {"status":"payload_size_mismatch","expected_size":expected,"actual_size":len(payload)}
    try: linear=_linearize(payload,metadata)
    except ValueError as e: return {"status":"layout_metadata_invalid","reason":str(e)}
    if linear is None: return {"status":"layout_conversion_required","reason":f'{metadata["layout"]} conversion is not validated'}
    destination=Path(destination); destination.parent.mkdir(parents=True,exist_ok=True)
    if fmt in {"BC1","BC2","BC3"}:
        destination=destination.with_suffix(".dds"); destination.write_bytes(_dds_header(w,h,fmt,len(linear))+linear)
    else:
        destination=destination.with_suffix(".tga")
        if fmt=="RGBA8":
            c=bytearray(len(linear))
            for i in range(0,len(linear),4): c[i:i+4]=bytes((linear[i+2],linear[i+1],linear[i],linear[i+3]))
            linear=bytes(c)
        tga=struct.pack("<BBBHHBHHHHBB",0,0,2,0,0,0,0,0,w,h,32,0x28); destination.write_bytes(tga+linear)
    return {"status":"runtime_texture_generated","path":str(destination)}
