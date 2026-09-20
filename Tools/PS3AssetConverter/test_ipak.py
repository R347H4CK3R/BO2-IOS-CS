import tempfile
import unittest
import zlib
from pathlib import Path

from ipak import DATA_HASH_MASK, IPakFile


class IPakTests(unittest.TestCase):
    def test_ps3_big_endian_ipak_structure_and_uncompressed_extract(self):
        chunk = 0x8000
        total_size = chunk * 3
        data = bytearray(b"\xA7" * total_size)

        data[0:4] = b"IPAK"
        data[4:8] = (0x50000).to_bytes(4, "big")
        data[8:12] = total_size.to_bytes(4, "big")
        data[12:16] = (2).to_bytes(4, "big")

        data_section_offset = chunk
        data_section_size = 0x200
        index_section_offset = chunk * 2
        index_section_size = 0x10

        data[16:20] = (2).to_bytes(4, "big")
        data[20:24] = data_section_offset.to_bytes(4, "big")
        data[24:28] = data_section_size.to_bytes(4, "big")
        data[28:32] = (1).to_bytes(4, "big")

        data[32:36] = (1).to_bytes(4, "big")
        data[36:40] = index_section_offset.to_bytes(4, "big")
        data[40:44] = index_section_size.to_bytes(4, "big")
        data[44:48] = (1).to_bytes(4, "big")

        payload = b"project-original-ipak-fixture"
        crc = zlib.crc32(payload) & DATA_HASH_MASK
        name_hash = 0x12345678

        # One uncompressed command.
        data[data_section_offset] = 1
        data[data_section_offset + 1 : data_section_offset + 4] = (0).to_bytes(3, "big")
        data[data_section_offset + 4] = 0
        data[data_section_offset + 5 : data_section_offset + 8] = len(payload).to_bytes(3, "big")
        data[data_section_offset + 0x80 : data_section_offset + 0x80 + len(payload)] = payload

        # PS3 index order: name hash, data CRC, relative offset, indexed size.
        data[index_section_offset : index_section_offset + 4] = name_hash.to_bytes(4, "big")
        data[index_section_offset + 4 : index_section_offset + 8] = crc.to_bytes(4, "big")
        data[index_section_offset + 8 : index_section_offset + 12] = (0).to_bytes(4, "big")
        data[index_section_offset + 12 : index_section_offset + 16] = (0x100).to_bytes(4, "big")

        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sample.ipak"
            path.write_bytes(data)
            ipak = IPakFile(path)
            inv = ipak.inventory()
            extracted = ipak.extract_entry(ipak.entries[0])

        self.assertEqual(inv["version"], 0x50000)
        self.assertEqual(len(inv["sections"]), 2)
        self.assertEqual(len(inv["entries"]), 1)
        self.assertEqual(inv["entries"][0]["name_hash"], name_hash)
        self.assertEqual(inv["entries"][0]["masked_data_crc"], crc)
        self.assertEqual(inv["entries"][0]["first_block"]["command_count"], 1)
        self.assertEqual(inv["entries"][0]["first_block"]["commands"][0]["compressed"], 0)
        self.assertEqual(extracted, payload)


if __name__ == "__main__":
    unittest.main()
