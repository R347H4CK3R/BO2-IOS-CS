import json, tempfile, unittest
from pathlib import Path
from convert_assets import detect, endian_probe, load_texture_metadata, scan
from runtime_texture import expected_payload_size, write_runtime_texture, unswizzle_morton, _morton2

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

    def test_linear_bc1_runtime_texture_writer(self):
        with tempfile.TemporaryDirectory() as d:
            meta = {"width":8,"height":8,"format":"BC1","layout":"linear"}
            payload = bytes(range(expected_payload_size(8, 8, "BC1")))
            result = write_runtime_texture(payload, meta, Path(d) / "texture")
            self.assertEqual(result["status"], "runtime_texture_generated")
            data = Path(result["path"]).read_bytes()
            self.assertEqual(data[:4], b"DDS ")
            self.assertEqual(len(data), 128 + len(payload))

    def test_runtime_texture_writer_rejects_unvalidated_layout_and_bad_size(self):
        with tempfile.TemporaryDirectory() as d:
            base = {"width":4,"height":4,"format":"BC1","layout":"ps3_tiled"}
            result = write_runtime_texture(b"12345678", base, Path(d) / "texture")
            self.assertEqual(result["status"], "layout_conversion_required")
            base["layout"] = "linear"
            result = write_runtime_texture(b"short", base, Path(d) / "texture")
            self.assertEqual(result["status"], "payload_size_mismatch")

    def test_rgba8_runtime_texture_channel_conversion(self):
        with tempfile.TemporaryDirectory() as d:
            meta = {"width":1,"height":1,"format":"RGBA8","layout":"linear"}
            result = write_runtime_texture(bytes((1,2,3,4)), meta, Path(d) / "pixel")
            data = Path(result["path"]).read_bytes()
            self.assertEqual(data[:3], bytes((0,0,2)))
            self.assertEqual(data[18:], bytes((3,2,1,4)))

    def test_authoritative_morton_swizzle_rgba8(self):
        with tempfile.TemporaryDirectory() as d:
            units=[bytes((i,i,i,255)) for i in range(8)]
            coords=sorted(((_morton2(x,y),x,y) for y in range(2) for x in range(4)))
            swizzled=b"".join(units[y*4+x] for _,x,y in coords)
            linear=unswizzle_morton(swizzled,4,2,4)
            self.assertEqual(linear,b"".join(units))
            meta={"width":4,"height":2,"format":"BGRA8","layout":"ps3_swizzled","swizzle":"morton2d"}
            result=write_runtime_texture(swizzled,meta,Path(d)/"morton")
            self.assertEqual(result["status"],"runtime_texture_generated")

    def test_swizzle_requires_explicit_algorithm(self):
        meta={"width":4,"height":4,"format":"BC1","layout":"ps3_swizzled"}
        payload=bytes(expected_payload_size(4,4,"BC1"))
        result=write_runtime_texture(payload,meta,Path("unused"))
        self.assertEqual(result["status"],"layout_metadata_invalid")

if __name__ == "__main__": unittest.main()
