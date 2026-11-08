import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]

class NoticePackagingTests(unittest.TestCase):
    def run_notice_stage(self, missing=False):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); app=root/'app';app.mkdir()
            (root/'Legal').mkdir();(root/'Legal/Xash3D-GPL-3.0.txt').write_text('GPL fixture')
            h=root/'Build/OpenSourceEngine/hlsdk-portable';h.mkdir(parents=True)
            s=root/'Build/OpenSourceEngine/SDL2';s.mkdir()
            (s/'LICENSE.txt').write_text('SDL license fixture')
            if not missing:(h/'LICENSE').write_text('HLSDK license fixture')
            script=(ROOT/'Scripts/package_xash_runtime.sh').read_text()
            block=script.split('# Keep the exact upstream legal notices',1)[1].split('mkdir -p "$APP/bo2ioscs"',1)[0]
            block='# Keep the exact upstream legal notices'+block
            result=subprocess.run(['bash','-e','-c',block],env=dict(os.environ,ROOT=str(root),APP=str(app)),capture_output=True)
            if missing:self.assertNotEqual(result.returncode,0)
            else:
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual((app/'Licenses/HLSDK.txt').read_bytes(),(h/'LICENSE').read_bytes())
                self.assertEqual((app/'Licenses/SDL2.txt').read_bytes(),(s/'LICENSE.txt').read_bytes())
                self.assertEqual((app/'Licenses/Xash3D-GPL-3.0.txt').read_text(),'GPL fixture')
    def test_copies_exact_notices(self):self.run_notice_stage()
    def test_rejects_missing_required_notice(self):self.run_notice_stage(missing=True)
    def test_validator_requires_notices(self):
        text=(ROOT/'Tools/validate_xash_ipa.sh').read_text()
        self.assertIn('[ -s "$APP/Licenses/HLSDK.txt" ]',text)
        self.assertIn('[ -s "$APP/Licenses/SDL2.txt" ]',text)
        self.assertIn('[ -s "$APP/Licenses/Xash3D-GPL-3.0.txt" ]',text)
