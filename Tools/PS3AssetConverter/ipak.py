from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
import ctypes
import ctypes.util
import struct
import zlib

IPAK_MAGIC = b"IPAK"
IPAK_VERSION = 0x50000
CHUNK_SIZE = 0x8000
BLOCK_ALIGN = 0x80
BLOCK_HEADER_SIZE = 0x80
COMMAND_UNCOMPRESSED = 0
COMMAND_COMPRESSED = 1
COMMAND_SKIP = 0xCF
DATA_HASH_MASK = 0x1FFFFFFF


@dataclass
class IPakSection:
    type: int
    offset: int
    size: int
    item_count: int

    def to_dict(self):
        return asdict(self)


@dataclass
class IPakIndexEntry:
    # PS3/T6 stores nameHash before dataHash in the big-endian file.
    name_hash: int
    data_hash: int
    offset: int
    size: int

    def to_dict(self):
        return asdict(self)


@dataclass
class IPakCommand:
    compressed: int
    size: int

    def to_dict(self):
        return asdict(self)


@dataclass
class IPakBlockHeader:
    relative_offset: int
    file_offset: int
    output_offset: int
    command_count: int
    commands: list[IPakCommand]

    def to_dict(self):
        return asdict(self)


def _align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


class LzoDecoder:
    def __init__(self):
        candidates = [
            ctypes.util.find_library("lzo2"),
            "/opt/homebrew/lib/liblzo2.dylib",
            "/usr/local/lib/liblzo2.dylib",
            "liblzo2.so.2",
            "liblzo2.so",
        ]
        last_error = None
        self.lib = None
        for candidate in candidates:
            if not candidate:
                continue
            try:
                self.lib = ctypes.CDLL(candidate)
                break
            except OSError as exc:
                last_error = exc
        if self.lib is None:
            raise RuntimeError(
                "LZO runtime not found. Install the open-source lzo library to extract "
                f"compressed IPAK commands. Last error: {last_error}"
            )

        self.decompress = self.lib.lzo1x_decompress_safe
        self.decompress.argtypes = [
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_size_t),
            ctypes.c_void_p,
        ]
        self.decompress.restype = ctypes.c_int

    def decode(self, data: bytes) -> bytes:
        capacity = max(0x10000, len(data) * 16)
        while capacity <= 64 * 1024 * 1024:
            output = ctypes.create_string_buffer(capacity)
            output_len = ctypes.c_size_t(capacity)
            result = self.decompress(
                data,
                len(data),
                output,
                ctypes.byref(output_len),
                None,
            )
            if result == 0:
                return output.raw[: output_len.value]
            # LZO_E_OUTPUT_OVERRUN is -5. Retry with a larger destination.
            if result == -5:
                capacity *= 2
                continue
            raise ValueError(f"LZO decompression failed with code {result}")
        raise ValueError("LZO output exceeded 64 MiB safety limit")


class IPakFile:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self.sections: list[IPakSection] = []
        self.entries: list[IPakIndexEntry] = []
        self._parse()

    def _u32(self, offset: int) -> int:
        return struct.unpack_from(">I", self.data, offset)[0]

    def _parse(self):
        if len(self.data) < 16:
            raise ValueError("IPAK too small")
        if self.data[:4] != IPAK_MAGIC:
            raise ValueError("invalid IPAK magic")

        self.version = self._u32(4)
        self.declared_size = self._u32(8)
        self.section_count = self._u32(12)

        if self.version != IPAK_VERSION:
            raise ValueError(f"unsupported IPAK version 0x{self.version:X}")
        if self.declared_size and self.declared_size != len(self.data):
            raise ValueError(
                f"declared IPAK size {self.declared_size} does not match actual size {len(self.data)}"
            )
        if len(self.data) % CHUNK_SIZE != 0:
            raise ValueError("IPAK file size is not aligned to 0x8000-byte chunks")

        section_offset = 16
        for _ in range(self.section_count):
            if section_offset + 16 > len(self.data):
                raise ValueError("truncated IPAK section table")
            section = IPakSection(
                type=self._u32(section_offset),
                offset=self._u32(section_offset + 4),
                size=self._u32(section_offset + 8),
                item_count=self._u32(section_offset + 12),
            )
            section_offset += 16
            if section.offset % CHUNK_SIZE != 0:
                raise ValueError(f"section at 0x{section.offset:X} is not chunk-aligned")
            if section.offset + section.size > len(self.data):
                raise ValueError("IPAK section exceeds file size")
            self.sections.append(section)

        self.data_section = next((s for s in self.sections if s.type == 2), None)
        self.index_section = next((s for s in self.sections if s.type == 1), None)

        if self.index_section:
            required = self.index_section.item_count * 16
            if required > self.index_section.size:
                raise ValueError("IPAK index item count exceeds index section size")
            for i in range(self.index_section.item_count):
                entry_offset = self.index_section.offset + i * 16
                self.entries.append(
                    IPakIndexEntry(
                        name_hash=self._u32(entry_offset),
                        data_hash=self._u32(entry_offset + 4),
                        offset=self._u32(entry_offset + 8),
                        size=self._u32(entry_offset + 12),
                    )
                )

    def parse_block(self, relative_offset: int) -> IPakBlockHeader:
        if not self.data_section:
            raise ValueError("IPAK has no data section")
        if relative_offset % BLOCK_ALIGN != 0:
            raise ValueError("IPAK block is not 0x80-byte aligned")

        file_offset = self.data_section.offset + relative_offset
        data_end = self.data_section.offset + self.data_section.size
        if file_offset + BLOCK_HEADER_SIZE > data_end:
            raise ValueError("IPAK block header exceeds data section")

        # PS3/big-endian T6 bitfields serialize the one-byte portion first,
        # followed by the 24-bit value.
        command_count = self.data[file_offset]
        output_offset = int.from_bytes(self.data[file_offset + 1 : file_offset + 4], "big")

        if command_count > 31:
            raise ValueError("IPAK block command count exceeds 31")

        commands: list[IPakCommand] = []
        for command_index in range(command_count):
            command_offset = file_offset + 4 + command_index * 4
            compressed = self.data[command_offset]
            stored_size = int.from_bytes(
                self.data[command_offset + 1 : command_offset + 4], "big"
            )
            commands.append(IPakCommand(compressed=compressed, size=stored_size))

        return IPakBlockHeader(
            relative_offset=relative_offset,
            file_offset=file_offset,
            output_offset=output_offset,
            command_count=command_count,
            commands=commands,
        )

    def extract_entry(self, entry: IPakIndexEntry, lzo: LzoDecoder | None = None) -> bytes:
        if not self.data_section:
            raise ValueError("IPAK has no data section")
        if entry.offset + entry.size > self.data_section.size:
            raise ValueError("IPAK index entry exceeds data section")

        output = bytearray()
        cursor = entry.offset
        entry_end = entry.offset + entry.size

        while cursor < entry_end:
            block = self.parse_block(cursor)
            command_data_offset = block.file_offset + BLOCK_HEADER_SIZE
            has_output_command = any(
                command.compressed in (COMMAND_UNCOMPRESSED, COMMAND_COMPRESSED)
                for command in block.commands
            )

            if has_output_command and block.output_offset != len(output):
                raise ValueError(
                    f"IPAK block output offset {block.output_offset} does not match "
                    f"current output length {len(output)}"
                )

            consumed = BLOCK_HEADER_SIZE
            for command in block.commands:
                command_end = command_data_offset + command.size
                absolute_entry_end = self.data_section.offset + entry_end
                if command_end > absolute_entry_end:
                    raise ValueError("IPAK command data exceeds indexed entry")

                payload = self.data[command_data_offset:command_end]
                command_data_offset = command_end
                consumed += command.size

                if command.compressed == COMMAND_UNCOMPRESSED:
                    output.extend(payload)
                elif command.compressed == COMMAND_COMPRESSED:
                    if lzo is None:
                        lzo = LzoDecoder()
                    output.extend(lzo.decode(payload))
                elif command.compressed == COMMAND_SKIP:
                    pass
                else:
                    # Unknown command modes are intentionally skipped, matching
                    # the game reader's tolerant behavior while retaining metadata.
                    pass

            next_cursor = _align(cursor + consumed, BLOCK_ALIGN)
            if next_cursor <= cursor:
                raise ValueError("IPAK parser made no progress")
            cursor = next_cursor

        actual_crc = zlib.crc32(output) & DATA_HASH_MASK
        expected_crc = entry.data_hash & DATA_HASH_MASK
        if actual_crc != expected_crc:
            raise ValueError(
                f"IPAK CRC mismatch: expected 0x{expected_crc:08X}, got 0x{actual_crc:08X}"
            )
        return bytes(output)

    def inventory(self):
        entries = []
        for entry in self.entries:
            item = entry.to_dict()
            item["masked_data_crc"] = entry.data_hash & DATA_HASH_MASK
            try:
                item["first_block"] = self.parse_block(entry.offset).to_dict()
            except Exception as exc:
                item["block_error"] = str(exc)
            entries.append(item)

        return {
            "magic": "IPAK",
            "version": self.version,
            "declared_size": self.declared_size,
            "actual_size": len(self.data),
            "chunk_size": CHUNK_SIZE,
            "sections": [section.to_dict() for section in self.sections],
            "entries": entries,
        }
