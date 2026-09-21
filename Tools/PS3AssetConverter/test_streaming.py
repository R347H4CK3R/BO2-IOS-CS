import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from convert_assets import scan

class StreamingScanTests(unittest.TestCase):
    def test_inventory_does_not_load_whole_unknown_files(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'source'
            source.mkdir()
            (source / 'large.bin').write_bytes(b'unknown')
            with patch.object(Path, 'read_bytes', side_effect=AssertionError('whole-file read')):
                result = scan(source, Path(folder) / 'out')
            self.assertEqual(result['files'][0]['errors'], [])
            self.assertEqual(result['files'][0]['conversion_status'], 'unsupported')
