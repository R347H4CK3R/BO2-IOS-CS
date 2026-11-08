from pathlib import Path
import os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
class XashCaptureTests(unittest.TestCase):
    def status(self,stderr='',live='Xash3D\nBO2IOSCS_RUNTIME_METADATA_LOADED\n'):
        with tempfile.TemporaryDirectory() as d:
            log=Path(d)
            for name in ('xash.log','xash-live.log','app-stdout.log','app-stderr.log'):(log/name).write_text('')
            (log/'app-stderr.log').write_text(stderr);(log/'xash-live.log').write_text(live)
            s=(ROOT/'Scripts/run_xash_simulator_test.sh').read_text()
            segment=s[s.index('AUTOTEST_MARKER=0'):s.index('cat > "$REPORT"')]
            result=subprocess.run(['bash','-c',segment+'\nprintf "%s" "$STATUS"'],env=dict(os.environ,LOGDIR=d),capture_output=True,text=True,check=True)
            return result.stdout
    def test_accepts_actual_early_marker_from_captured_stderr(self):
        self.assertEqual(self.status(stderr='BO2IOSCS_AUTOTEST launch path enabled\n'),'PASS')
    def test_missing_marker_still_fails(self):self.assertEqual(self.status(),'FAIL')
    def test_fatal_stderr_still_fails(self):
        self.assertEqual(self.status(stderr='fatal error\n',live='Xash3D\nBO2IOSCS_RUNTIME_METADATA_LOADED\nBO2IOSCS_AUTOTEST launch path enabled\n'),'FAIL')
