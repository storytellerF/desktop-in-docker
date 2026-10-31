"""Run as the desktop user in a running MATE, Cinnamon or KDE container."""

import argparse
import os
from pathlib import Path
import stat
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


KEYBOARD_INPUT = """
import ctypes as c
import os, sys
x = c.CDLL('libX11.so.6')
t = c.CDLL('libXtst.so.6')
x.XOpenDisplay.argtypes = [c.c_char_p]
x.XOpenDisplay.restype = c.c_void_p
x.XStringToKeysym.argtypes = [c.c_char_p]
x.XStringToKeysym.restype = c.c_ulong
x.XKeysymToKeycode.argtypes = [c.c_void_p, c.c_ulong]
x.XKeysymToKeycode.restype = c.c_uint
t.XTestFakeKeyEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]
x.XSync.argtypes = [c.c_void_p, c.c_int]
x.XCloseDisplay.argtypes = [c.c_void_p]
d = x.XOpenDisplay(os.environ['DISPLAY'].encode())
assert d, 'Cannot open the session display'
try:
 keys = [x.XKeysymToKeycode(d, x.XStringToKeysym(k.encode())) for k in sys.argv[1:]]
 if not all(keys): sys.exit(77)
 for key in keys: assert t.XTestFakeKeyEvent(d, key, 1, 0)
 for key in reversed(keys): assert t.XTestFakeKeyEvent(d, key, 0, 0)
 x.XSync(d, 0)
finally: x.XCloseDisplay(d)
"""

SCREEN_SAVER_TIMEOUT = """
import ctypes as c, os
x = c.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes = [c.c_char_p]
x.XOpenDisplay.restype = c.c_void_p
x.XGetScreenSaver.argtypes = [c.c_void_p, *[c.POINTER(c.c_int)] * 4]
x.XCloseDisplay.argtypes = [c.c_void_p]
d = x.XOpenDisplay(os.environ['DISPLAY'].encode())
assert d, 'Cannot open the session display'
values = [c.c_int() for _ in range(4)]
try:
 x.XGetScreenSaver(d, *[c.byref(value) for value in values])
 print(values[0].value)
finally: x.XCloseDisplay(d)
"""


class DesktopLockingTests(unittest.TestCase):
    desktop = None

    @classmethod
    def setUpClass(cls):
        for proc in Path("/proc").iterdir():
            try:
                if proc.stat().st_uid != os.getuid():
                    continue
                if (proc / "comm").read_text().strip() != f"{cls.desktop}-session"[:15]:
                    continue
                cls.environment = dict(item.split("=", 1) for item in
                                       (proc / "environ").read_text().split("\0") if "=" in item)
                cls.environment["LC_ALL"] = "C"
                cls.schema = "org.mate" if cls.desktop == "mate" else "org.cinnamon.desktop"
                cls.bus_name = f"org.{cls.desktop}.ScreenSaver"
                return
            except OSError:
                continue
        raise AssertionError("Running desktop session not found")

    def run_command(self, *args):
        return subprocess.run(args, env=self.environment, check=True, capture_output=True,
                              text=True, timeout=15).stdout.strip()

    def assert_locker_inactive(self):
        result = self.run_command("dbus-send", "--session", "--print-reply",
                                  "--dest=org.freedesktop.DBus", "/org/freedesktop/DBus",
                                  "org.freedesktop.DBus.NameHasOwner", "string:" + self.bus_name)
        self.assertIn("boolean false", result)
        for proc in Path("/proc").iterdir():
            try:
                name = (proc / "comm").read_text().strip()
            except OSError:
                continue
            self.assertNotEqual(name, f"{self.desktop}-screensaver"[:15])

    def test_idle_activation_is_disabled(self):
        if not Path(f"/usr/bin/{self.desktop}-screensaver").exists():
            self.assert_locker_inactive()
            return
        self.assertEqual(self.run_command("gsettings", "get", self.schema + ".screensaver",
                                          "idle-activation-enabled"), "false")
        self.assertEqual(self.run_command(sys.executable, "-c", SCREEN_SAVER_TIMEOUT), "0")

    def test_password_locking_is_disabled(self):
        if self.desktop == "mate":
            self.assertEqual(self.run_command("gsettings", "get", "org.mate.lockdown",
                                              "disable-lock-screen"), "true")
        if not Path(f"/usr/bin/{self.desktop}-screensaver").exists():
            self.assert_locker_inactive()
            return
        self.assertEqual(self.run_command("gsettings", "get", self.schema + ".screensaver",
                                          "lock-enabled"), "false")
        self.assertEqual(self.run_command("gsettings", "get", self.schema + ".lockdown",
                                          "disable-lock-screen"), "true")

    def test_locker_cannot_autostart_or_activate_over_dbus(self):
        self.assert_locker_inactive()
        binary = Path(f"/usr/bin/{self.desktop}-screensaver")
        if binary.exists():
            self.assertEqual(binary.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), 0)
        # Some distributions put the service file in a separate data package.
        # An inert activation file is harmless when its daemon cannot execute.
        result = subprocess.run(["dbus-send", "--session", "--print-reply", "--reply-timeout=5000",
                                 "--dest=" + self.bus_name, f"/org/{self.desktop}/ScreenSaver",
                                 self.bus_name + ".Lock"], env=self.environment,
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_locker_inactive()

    def assert_request_cannot_activate(self, flag):
        command = shutil.which(self.desktop + "-screensaver-command")
        if command:
            subprocess.run([command, flag], env=self.environment,
                           capture_output=True, text=True, timeout=15)
        self.assert_locker_inactive()

    def test_manual_lock_cannot_activate_a_screensaver(self):
        self.assert_request_cannot_activate("--lock")

    def test_manual_blanking_cannot_activate_a_screensaver(self):
        self.assert_request_cannot_activate("--activate")

    def test_lock_shortcut_settings_are_empty(self):
        if self.desktop == "mate":
            self.assertEqual(self.run_command("gsettings", "get", "org.mate.SettingsDaemon.plugins.media-keys",
                                              "screensaver"), "''")
            return
        if not Path(f"/usr/bin/{self.desktop}-screensaver").exists():
            self.assert_locker_inactive()
            return
        keys = (("org.cinnamon.desktop.keybindings.media-keys", "screensaver"),
                    ("org.cinnamon.settings-daemon.plugins.media-keys", "screensaver"),
                    ("org.cinnamon.desktop.keybindings", "looking-glass-keybinding"))
        for schema, key in keys:
            with self.subTest(schema=schema, key=key):
                self.assertIn(self.run_command("gsettings", "get", schema, key), ("''", "[]", "@as []"))

    def assert_shortcut_cannot_activate(self, *keys):
        result = subprocess.run([sys.executable, "-c", KEYBOARD_INPUT, *keys],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        if result.returncode == 77:
            self.skipTest("The virtual keyboard has no mapping for " + "+".join(keys))
        self.assertEqual(result.returncode, 0, result.stderr)
        time.sleep(0.5)
        self.assert_locker_inactive()

    def test_ctrl_alt_l_cannot_activate_a_screensaver(self):
        self.assert_shortcut_cannot_activate("Control_L", "Alt_L", "l")

    def test_super_l_cannot_activate_a_screensaver(self):
        self.assert_shortcut_cannot_activate("Super_L", "l")

    def test_hardware_lock_key_cannot_activate_a_screensaver(self):
        self.assert_shortcut_cannot_activate("XF86ScreenSaver")


class KdeLockingTests(unittest.TestCase):
    run_command = DesktopLockingTests.run_command
    assert_shortcut_cannot_activate = DesktopLockingTests.assert_shortcut_cannot_activate
    test_ctrl_alt_l_cannot_activate_a_screensaver = DesktopLockingTests.test_ctrl_alt_l_cannot_activate_a_screensaver
    test_super_l_cannot_activate_a_screensaver = DesktopLockingTests.test_super_l_cannot_activate_a_screensaver
    test_hardware_lock_key_cannot_activate_a_screensaver = DesktopLockingTests.test_hardware_lock_key_cannot_activate_a_screensaver

    @classmethod
    def setUpClass(cls):
        for proc in Path("/proc").iterdir():
            try:
                if proc.stat().st_uid == os.getuid() and (proc / "comm").read_text().strip() == "plasmashell":
                    cls.environment = dict(item.split("=", 1) for item in
                                           (proc / "environ").read_text().split("\0") if "=" in item)
                    cls.environment["LC_ALL"] = "C"
                    cls.reader = shutil.which("kreadconfig6") or shutil.which("kreadconfig5")
                    if not cls.reader:
                        raise AssertionError("KDE's native configuration reader not found")
                    return
            except OSError:
                continue
        raise AssertionError("Running Plasma session not found")

    def assert_locker_inactive(self):
        result = self.run_command("dbus-send", "--session", "--print-reply",
                                  "--dest=org.freedesktop.ScreenSaver", "/ScreenSaver",
                                  "org.freedesktop.ScreenSaver.GetActive")
        self.assertIn("boolean false", result)

    def read_setting(self, file, group, key, environment=None):
        return subprocess.run([self.reader, "--file", file, "--group", group, "--key", key],
                              env=environment or self.environment, check=True, capture_output=True,
                              text=True, timeout=10).stdout.strip()

    def test_native_action_policy_disables_menu_shortcut_and_dbus_lock(self):
        self.assertEqual(self.read_setting("kdeglobals", "KDE Action Restrictions", "action/lock_screen"), "false")

    def test_native_idle_resume_and_startup_locking_are_disabled(self):
        for key in ("Autolock", "LockOnResume", "LockOnStart"):
            with self.subTest(key=key):
                self.assertEqual(self.read_setting("kscreenlockerrc", "Daemon", key), "false")

    def test_existing_user_preferences_cannot_override_system_lock_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "kdeglobals").write_text("[KDE Action Restrictions]\naction/lock_screen=true\n")
            (root / "kscreenlockerrc").write_text("[Daemon]\nAutolock=true\nLockOnResume=true\n")
            env = dict(self.environment, XDG_CONFIG_HOME=directory)
            self.assertEqual(self.read_setting("kdeglobals", "KDE Action Restrictions", "action/lock_screen", env), "false")
            self.assertEqual(self.read_setting("kscreenlockerrc", "Daemon", "Autolock", env), "false")

    def test_dbus_lock_request_cannot_activate_locker(self):
        self.run_command("dbus-send", "--session", "--print-reply", "--reply-timeout=5000",
                         "--dest=org.freedesktop.ScreenSaver", "/ScreenSaver",
                         "org.freedesktop.ScreenSaver.Lock")
        self.assert_locker_inactive()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop", required=True, choices=("mate", "cinnamon", "kde"))
    args, rest = parser.parse_known_args()
    DesktopLockingTests.desktop = args.desktop
    unittest.main(argv=[__file__, *rest],
                  defaultTest="KdeLockingTests" if args.desktop == "kde" else "DesktopLockingTests")
