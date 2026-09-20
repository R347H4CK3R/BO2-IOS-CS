from __future__ import annotations
from dataclasses import dataclass, asdict
from pathlib import Path
import struct

@dataclass
class FastFileHeader:
    magic: str
    version: int
    auth_magic: str
    reserved: int
    name: str
    signature_offset: int
    signature_size: int
    payload_offset: int
    encrypted_payload: bool

    def to_dict(self):
        return asdict(self)

def parse_fastfile_header(path: Path) -> FastFileHeader:
    data = path.read_bytes()
    if len(data) < 312:
        raise ValueError("fastfile too small for authenticated BO2 header")
    magic = data[0:8].decode("ascii", errors="replace")
    if magic != "TAff0100":
        raise ValueError(f"unsupported fastfile magic: {magic!r}")
    version = struct.unpack(">I", data[8:12])[0]
    auth_magic = data[12:20].decode("ascii", errors="replace")
    reserved = struct.unpack(">I", data[20:24])[0]
    name = data[24:56].split(b"\0", 1)[0].decode("ascii", errors="replace")
    if auth_magic != "PHEEBs71":
        raise ValueError(f"unexpected BO2 auth magic: {auth_magic!r}")
    return FastFileHeader(
        magic=magic,
        version=version,
        auth_magic=auth_magic,
        reserved=reserved,
        name=name,
        signature_offset=56,
        signature_size=256,
        payload_offset=312,
        encrypted_payload=True,
    )
