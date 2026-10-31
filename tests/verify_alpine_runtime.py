"""Run inside an Alpine desktop container as its desktop user after startup.

    python3 verify_alpine_runtime.py --desktop cinnamon

This checks installed dependencies and the running session, not Dockerfile text.
"""

import argparse
import os
from pathlib import Path
import shutil
import stat
import subprocess
import unittest


SESSIONS = {
    "xfce": "xfce4-session", "lxqt": "lxqt-session", "mate": "mate-session",
    "kde": "plasmashell", "gnome": "gnome-shell", "cinnamon": "cinnamon",
    "lxde": "lxsession", "enlightenment": "enlightenment",
}


class AlpineRuntimeTests(unittest.TestCase):
    desktop = None
    variant = None

    @classmethod
    def setUpClass(cls):
        # Only inspect this user's actual desktop process, excluding launchers.
        for proc in Path("/proc").iterdir():
            if not proc.name.isdigit():
                continue
            try:
                if proc.stat().st_uid != os.getuid():
                    continue
                if (proc / "comm").read_text().strip() != SESSIONS[cls.desktop]:
                    continue
                cls.session = proc
                cls.environment = dict(
                    item.split("=", 1) for item in
                    (proc / "environ").read_text().split("\0") if "=" in item
                )
                return
            except (OSError, ProcessLookupError):
                continue
        raise AssertionError(f"Running {cls.desktop} desktop process was not found")

    def test_session_bus(self):
        self.assertIn("DBUS_SESSION_BUS_ADDRESS", self.environment)
        subprocess.run([
            "dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.DBus",
            "/org/freedesktop/DBus", "org.freedesktop.DBus.ListNames",
        ], env=self.environment, check=True, capture_output=True, timeout=10)

    def test_session_descriptor_limit(self):
        line = next(line for line in (self.session / "limits").read_text().splitlines()
                    if line.startswith("Max open files"))
        soft, hard = line.split()[3:5]
        self.assertNotEqual(hard, "unlimited")
        self.assertLessEqual(int(hard), 65536)
        self.assertLessEqual(int(soft), int(hard))

    def test_desktop_runtime_dependencies(self):
        if self.desktop == "kde" and self.variant == "x11":
            subprocess.run([
                "apk", "info", "--installed", "plasma-workspace-wallpapers", "breeze-icons",
                "kglobalacceld", "kquickcharts", "kpipewire", "breeze", "plasma-pa",
            ], check=True, capture_output=True, timeout=10)
            self.assertTrue((Path("/usr/share/wallpapers/Next") / "metadata.json").is_file())
            for launcher in ("systemsettings.desktop", "org.kde.discover.desktop"):
                self.assertTrue((Path("/usr/share/applications") / launcher).is_file(), launcher)
        if self.desktop == "enlightenment":
            version = subprocess.run(["enlightenment", "--version"], text=True,
                                     capture_output=True, timeout=10)
            # Upstream 0.27.1 deliberately exits through _e_main_shutdown(11).
            self.assertEqual(version.returncode, 11, version.stderr)
            self.assertIn("Version: 0.27.1", version.stdout)
            modules = Path("/usr/lib/enlightenment/modules")
            self.assertTrue(list((modules / "polkit").rglob("module.so")))
            for module in modules.rglob("*.so"):
                loaded = subprocess.run(["ldd", str(module)], text=True,
                                        capture_output=True, timeout=10)
                self.assertNotIn("Error loading shared library", loaded.stdout + loaded.stderr,
                                 str(module))
        if self.desktop == "cinnamon":
            schemas = subprocess.check_output(["gsettings", "list-schemas"], text=True)
            for schema in ("org.gnome.desktop.interface", "org.gnome.desktop.input-sources"):
                self.assertIn(schema, schemas.splitlines())
            subprocess.run([
                "python3", "-c", "import gi; gi.require_version('PolkitAgent', '1.0'); "
                "gi.require_version('NM', '1.0'); "
                "gi.require_version('AccountsService', '1.0'); gi.require_version('IBus', '1.0'); "
                "from gi.repository import PolkitAgent, NM, AccountsService, IBus; "
                "assert all(t.__gtype__.name != 'void' for t in "
                "(PolkitAgent.Listener, NM.Client, AccountsService.UserManager, IBus.Bus)); "
                "import xapp.os; import cairo",
            ], check=True, capture_output=True, timeout=10)
        if self.desktop in ("cinnamon", "gnome", "kde") and self.variant == "x11":
            runtime = Path(self.environment["XDG_RUNTIME_DIR"])
            self.assertEqual(runtime.stat().st_uid, os.getuid())
            # GNOME may retain setgid on this directory; only owner access is required.
            self.assertEqual(stat.S_IMODE(runtime.stat().st_mode) & 0o777, 0o700)
            subprocess.run([
                "dbus-send", "--system", "--print-reply", "--dest=org.freedesktop.DBus",
                "/org/freedesktop/DBus", "org.freedesktop.DBus.ListNames",
            ], check=True, capture_output=True, timeout=10)
        commands = {
            "kde": (("startplasma-x11", "kwin_x11") if self.variant == "x11"
                    else ("plasmashell",)),
            "lxde": ("lxpanel", "lxsession", "openbox", "pcmanfm"),
            "enlightenment": ("enlightenment_start", "terminology"),
        }.get(self.desktop, ())
        for command in commands:
            self.assertIsNotNone(shutil.which(command), command)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop", required=True, choices=SESSIONS)
    parser.add_argument("--variant", choices=("x11", "webtop"), default="x11")
    args = parser.parse_args()
    AlpineRuntimeTests.desktop = args.desktop
    AlpineRuntimeTests.variant = args.variant
    unittest.main(argv=[__file__, "-v"])
