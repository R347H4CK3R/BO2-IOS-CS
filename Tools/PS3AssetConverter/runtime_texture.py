#!/usr/bin/env python3
"""Strict runtime texture writer for already-decoded payloads with authoritative metadata.

This module performs no container decryption, metadata inference, untile, or unswizzle.
Non-linear layouts are deliberately rejected until a separately validated transform exists.
"""
import struct
from pathlib import Path


def expected_payload_size(width, height, fmt):
    if fmt == "BC1":
        return ((width + 3) // 4) * ((height + 3) // 4) * 8
    if fmt in {"BC2", "BC3"}:
        return ((width + 3) // 4) * ((height + 3) // 4) * 16
    if fmt in {"RGBA8", "BGRA8"}:
        return width * height * 4
    return None


def _dds_header(width, height, fmt, payload_size):
    fourcc = {"BC1": b"DXT1", "BC2": b"DXT3", "BC3": b"DXT5"}[fmt]
    flags = 0x00081007  # CAPS | HEIGHT | WIDTH | PIXELFORMAT | LINEARSIZE
    header = struct.pack("<IIIIIII11I", 124, flags, height, width, payload_size, 0, 1, *([0] * 11))
    pixel_format = struct.pack("<II4sIIIII", 32, 0x4, fourcc, 0, 0, 0, 0, 0)
    caps = struct.pack("<IIIII", 0x1000, 0, 0, 0, 0)
    return b"DDS " + header + pixel_format + caps


def write_runtime_texture(payload, metadata, destination):
    width, height = metadata["width"], metadata["height"]
    fmt, layout = metadata["format"], metadata["layout"]
    if layout != "linear":
        return {"status": "layout_conversion_required", "reason": f"{layout} is not treated as linear"}
    expected = expected_payload_size(width, height, fmt)
    if expected is None:
        return {"status": "format_conversion_required", "reason": f"{fmt} export is not validated"}
    if len(payload) != expected:
        return {"status": "payload_size_mismatch", "expected_size": expected, "actual_size": len(payload)}

    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if fmt in {"BC1", "BC2", "BC3"}:
        destination = destination.with_suffix(".dds")
        destination.write_bytes(_dds_header(width, height, fmt, len(payload)) + payload)
    else:
        destination = destination.with_suffix(".tga")
        if fmt == "RGBA8":
            converted = bytearray(len(payload))
            for i in range(0, len(payload), 4):
                converted[i:i+4] = bytes((payload[i+2], payload[i+1], payload[i], payload[i+3]))
            pixels = bytes(converted)
        else:
            pixels = payload
        # Uncompressed true-color TGA, top-left origin, 8 alpha bits.
        tga = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
        destination.write_bytes(tga + pixels)
    return {"status": "runtime_texture_generated", "path": str(destination)}
