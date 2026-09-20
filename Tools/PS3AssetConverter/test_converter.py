import tempfile, unittest
from pathlib import Path
from convert_assets import detect, endian_probe, scan

class ConverterTests(unittest.TestCase):
    def test_signature_and_endian(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.bin"
            p.write_bytes(b"DDS " + b"1234")
            self.assertEqual(detect(p), ("dds", "texture"))
            self.assertEqual(endian_probe(p)["u32_be"], int.from_bytes(b"DDS ", "big"))

    def test_unknown_is_preserved_in_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            src, out = Path(d) / "src", Path(d) / "out"
            src.mkdir()
            (src / "mystery.xyz").write_bytes(b"abcdef")
            inv = scan(src, out)
            self.assertEqual(inv["files"][0]["conversion_status"], "unsupported")
            self.assertTrue((out / "asset_inventory.json").exists())

if __name__ == "__main__":
    unittest.main()
