import json, tempfile, unittest
from pathlib import Path
from convert_assets import detect, endian_probe, load_texture_metadata, scan

class ConverterTests(unittest.TestCase):
    def test_signature_and_endian(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.bin"; p.write_bytes(b"DDS " + b"1234")
            self.assertEqual(detect(p), ("dds", "texture"))
            self.assertEqual(endian_probe(p)["u32_be"], int.from_bytes(b"DDS ", "big"))

    def test_unknown_is_preserved_in_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            src, out = Path(d) / "src", Path(d) / "out"; src.mkdir(); (src / "mystery.xyz").write_bytes(b"abcdef")
            inv = scan(src, out)
            self.assertEqual(inv["files"][0]["conversion_status"], "unsupported")
            self.assertTrue((out / "asset_inventory.json").exists())

    def test_texture_metadata_requires_authoritative_fields(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "metadata.json"
            p.write_text(json.dumps({"schema":"bo2ioscs-texture-metadata-v1","textures":[{"name_hash":"0x1234ABCD","data_crc":None,"width":256,"height":128,"format":"BC1","layout":"linear"}]}))
            mapped = load_texture_metadata(p)
            self.assertEqual(mapped[(0x1234ABCD, None)]["width"], 256)
            p.write_text(json.dumps({"schema":"bo2ioscs-texture-metadata-v1","textures":[{"name_hash":"0x1234ABCD","width":256,"height":128,"format":"BC1","layout":"guessed"}]}))
            with self.assertRaises(ValueError): load_texture_metadata(p)

    def test_texture_metadata_rejects_bad_schema_and_duplicates(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "metadata.json"; p.write_text('{"schema":"wrong","textures":[]}')
            with self.assertRaises(ValueError): load_texture_metadata(p)
            item = {"name_hash":"0x1234ABCD","width":1,"height":1,"format":"RGBA8","layout":"linear"}
            p.write_text(json.dumps({"schema":"bo2ioscs-texture-metadata-v1","textures":[item,item]}))
            with self.assertRaises(ValueError): load_texture_metadata(p)

if __name__ == "__main__": unittest.main()
