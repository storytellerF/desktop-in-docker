"""Native session policies are applied before starting their desktops."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SESSION_DIR = Path(__file__).resolve().parents[1] / "docker/config/session"


class SessionPolicyContract:
    def run_session(self, settings_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, body in {
                    self.settings_command: 'printf "%s\\n" "$*" >> "$TRACE"; exit "$SETTINGS_EXIT"',
                    self.desktop_command: 'printf "desktop-started\\n" >> "$TRACE"; exit 7'}.items():
                path = root / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            trace = root / "trace"
            env = dict(os.environ, PATH=str(root), TRACE=str(trace), SETTINGS_EXIT=str(settings_exit))
            result = subprocess.run(["/bin/sh", str(SESSION_DIR / self.script)], env=env, capture_output=True,
                                    text=True, timeout=10)
            return result, trace.read_text().splitlines()

    def test_native_policy_is_applied_before_desktop_start(self):
        result, trace = self.run_session()
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(trace, [*self.expected_settings, "desktop-started"])

    def test_policy_failure_stops_before_starting_desktop(self):
        result, trace = self.run_session(settings_exit=9)
        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertEqual(len(trace), 1)
        self.assertNotIn("desktop-started", trace)


@unittest.skipUnless(os.name == "posix", "Desktop sessions run inside Linux containers")
class XfceSessionTests(SessionPolicyContract, unittest.TestCase):
    script = "start-xfce-unblanked.sh"
    settings_command = "xfconf-query"
    desktop_command = "startxfce4"
    expected_settings = [
        "--channel xfce4-power-manager --property /xfce4-power-manager/blank-on-ac --create --type int --set 0",
        "--channel xfce4-power-manager --property /xfce4-power-manager/blank-on-battery --create --type int --set 0"]


@unittest.skipUnless(os.name == "posix", "Desktop sessions run inside Linux containers")
class MateSessionTests(SessionPolicyContract, unittest.TestCase):
    script = "start-mate-unlocked.sh"
    settings_command = "gsettings"
    desktop_command = "mate-session"
    expected_settings = [
        "set org.mate.lockdown disable-lock-screen true",
        "set org.mate.SettingsDaemon.plugins.media-keys screensaver ''"]
