import importlib.util
import subprocess
from pathlib import Path
import tempfile
import unittest
import zipfile

p=Path(__file__).resolve().parents[2]/'Scripts/archive_xash_sources.py'
spec=importlib.util.spec_from_file_location('source_archive',p);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class SourceArchiveTests(unittest.TestCase):
    def repo(self,root):
        subprocess.run(['git','init','-q',str(root)],check=True)
        (root/'source.c').write_text('original')
        subprocess.run(['git','-C',str(root),'add','source.c'],check=True)
        subprocess.run(['git','-C',str(root),'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture'],check=True)
    def test_includes_applied_patch_not_untracked_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'repo';root.mkdir();self.repo(root)
            (root/'source.c').write_text('patched');(root/'untracked.txt').write_text('must not archive')
            output=Path(temp)/'source.zip';module.archive_sources({'component':root},output)
            with zipfile.ZipFile(output) as z:
                self.assertEqual(z.read('component/source.c'),b'patched')
                self.assertNotIn('component/untracked.txt',z.namelist())
                self.assertIn('SOURCE-MANIFEST.json',z.namelist())
    def test_rejects_tracked_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'repo';root.mkdir();self.repo(root)
            (root/'link').symlink_to('/etc/passwd')
            subprocess.run(['git','-C',str(root),'add','link'],check=True)
            with self.assertRaises(ValueError):list(module.tracked_files(root))

    def test_preserves_relative_source_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'repo';root.mkdir();self.repo(root)
            (root/'link').symlink_to('source.c')
            subprocess.run(['git','-C',str(root),'add','link'],check=True)
            output=Path(temp)/'source.zip';module.archive_sources({'component':root},output)
            with zipfile.ZipFile(output) as z:
                self.assertEqual(z.read('component/link'),b'source.c')
                self.assertEqual((z.getinfo('component/link').external_attr>>16)&0o170000,0o120000)
