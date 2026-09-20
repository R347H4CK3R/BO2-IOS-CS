import tempfile
import unittest
from pathlib import Path

from ipak import IPakFile


class IPakTests(unittest.TestCase):
    def test_ps3_big_endian_ipak_structure(self):
        chunk = 0x8000
        total_size = chunk * 3
        data = bytearray(b"\xA7" * total_size)

        # Header: magic, version, size, section count.
        data[0:4] = b"IPAK"
        data[4:8] = (0x50000).to_bytes(4, "big")
        data[8:12] = total_size.to_bytes(4, "big")
        data[12:16] = (2).to_bytes(4, "big")

        data_section_offset = chunk
        data_section_size = 0x200
        index_section_offset = chunk * 2
        index_section_size = 0x10

        # Data section.
        data[16:20] = (2).to_bytes(4, "big")
        data[20:24] = data_section_offset.to_bytes(4, "big")
        data[24:28] = data_section_size.to_bytes(4, "big")
        data[28:32] = (1).to_bytes(4, "big")

        # Index section.
        data[32:36] = (1).to_bytes(4, "big")
        data[36:40] = index_section_offset.to_bytes(4, "big")
        data[40:44] = index_section_size.to_bytes(4, "big")
        data[44:48] = (1).to_bytes(4, "big")

        # First block: one compressed command, output offset 0, stored size 0x20.
        data[data_section_offset] = 1
        data[data_section_offset + 1 : data_section_offset + 4] = (0).to_bytes(3, "big")
        data[data_section_offset + 4] = 1
        data[data_section_offset + 5 : data_section_offset + 8] = (0x20).to_bytes(3, "big")

        # Index entry.
        data[index_section_offset : index_section_offset + 4] = (0x12345678).to_bytes(4, "big")
        data[index_section_offset + 4 : index_section_offset + 8] = (0x9ABCDEF0).to_bytes(4, "big")
        data[index_section_offset + 8 : index_section_offset + 12] = (0).to_bytes(4, "big")
        data[index_section_offset + 12 : index_section_offset + 16] = (0x180).to_bytes(4, "big")

        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sample.ipak"
            path.write_bytes(data)
            ipak = IPakFile(path)
            inv = ipak.inventory()

        self.assertEqual(inv["version"], 0x50000)
        self.assertEqual(len(inv["sections"]), 2)
        self.assertEqual(len(inv["entries"]), 1)
        self.assertEqual(inv["entries"][0]["data_hash"], 0x12345678)
        self.assertEqual(inv["entries"][0]["first_block"]["command_count"], 1)
        self.assertEqual(inv["entries"][0]["first_block"]["commands"][0]["compressed"], 1)
        self.assertEqual(inv["entries"][0]["first_block"]["commands"][0]["size"], 0x20)


if __name__ == "__main__":
    unittest.main()
