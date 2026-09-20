import tempfile
import unittest
from pathlib import Path
from fastfile import parse_fastfile_header

class FastFileTests(unittest.TestCase):
    def test_bo2_ps3_header(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "sample.ff"
            name = b"sample_zone" + b"\0" * (32 - len("sample_zone"))
            data = b"TAff0100" + (0x92).to_bytes(4, "big") + b"PHEEBs71" + (0).to_bytes(4, "big") + name + b"\0" * 256 + b"encrypted"
            p.write_bytes(data)
            h = parse_fastfile_header(p)
            self.assertEqual(h.version, 0x92)
            self.assertEqual(h.name, "sample_zone")
            self.assertEqual(h.payload_offset, 312)
            self.assertTrue(h.encrypted_payload)

if __name__ == "__main__":
    unittest.main()
