"""Exercise the optional Node-based OpenClaw wire adapter without user state."""
from pathlib import Path
import shutil
import subprocess
import unittest


class OpenClawMonitorTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "OpenClaw's Node runtime is not installed")
    def test_wire_and_secret_ref_fixtures(self):
        subprocess.run(["node", "--disable-warning=ExperimentalWarning", "--test",
                        str(Path(__file__).with_name("openclaw-monitor.mjs"))], check=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
