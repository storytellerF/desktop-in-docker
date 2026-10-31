"""The VNC server disables its own idle blanking without an xset dependency."""

import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
import sys


SCRIPT = Path(__file__).resolve().parents[1] / "base-scripts/start-vnc.sh"


@unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("bash"), "VNC runtime requires Linux/Bash")
class VncScreensaverTests(unittest.TestCase):
    def run_startup(self, legacy_config=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home = root / "home"
            home.mkdir()
            if legacy_config is not None:
                (home / ".vnc").mkdir()
                (home / ".vnc/config").write_text(legacy_config)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for name, body in {
                    "vncserver": 'cp "$HOME/.config/tigervnc/config" "$VNC_SNAPSHOT"',
                    "sleep": 'exit 0',
                    # The real script cleans the display's global socket paths.
                    "rm": 'exit 0'}.items():
                path = bin_dir / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            snapshot = root / "config-at-server-start"
            env = dict(os.environ, HOME=str(home), VNC_PASSWD="", VNC_SNAPSHOT=str(snapshot),
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            result = subprocess.run([shutil.which("bash"), str(SCRIPT)], env=env, cwd=root,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return snapshot.read_text(), (home / ".vnc/config").read_text()

    def test_server_reads_zero_screensaver_timeout_from_config(self):
        config, _ = self.run_startup()
        self.assertIn("s=0", config.splitlines())

    def test_existing_legacy_config_disables_blanking_and_keeps_other_options(self):
        _, legacy = self.run_startup("geometry=640x480\n s =600\nlocalhost=yes\n")
        self.assertEqual(legacy, "geometry=640x480\ns=0\nlocalhost=yes\n")


if __name__ == "__main__":
    unittest.main()
