"""Package policies preserve desktops while removing optional screen lockers."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "docker/build" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


install = load("screensaver-packages")
remove = load("remove-optional-screensavers")


class AlpineDesktopPackagesTests(unittest.TestCase):
    def test_components_keep_versioned_apps_and_power_management(self):
        self.assertEqual(install.components("caja\nmate-power-manager>=1.28\n"
                                             "mate-screensaver>=1.28\nxscreensaver\n"),
                         ["caja", "mate-power-manager>=1.28"])

    def test_invalid_or_empty_metadata_fails_before_package_installation(self):
        for text in ("", "mate-screensaver", "error: no such package", "app;touch"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                install.components(text)

    def test_failed_metadata_query_does_not_install_partial_desktop(self):
        with patch.object(install.subprocess, "run", side_effect=[
                subprocess.CompletedProcess([], 0),
                subprocess.CalledProcessError(1, ["apk", "info"])]) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                install.main(["lxqt-desktop"])
            self.assertEqual(run.call_count, 2)


class OptionalRemovalTests(unittest.TestCase):
    def setUp(self):
        policy = patch.object(remove, "disable_required_xscreensaver")
        policy.start()
        self.addCleanup(policy.stop)

    def test_failed_alpine_component_preservation_does_not_delete_metapackage(self):
        def command(*args):
            if args[:3] == ("apk", "info", "-e"):
                return subprocess.CompletedProcess(args, 0, "", "")
            if args[:4] == ("apk", "-q", "info", "-R"):
                return subprocess.CompletedProcess(args, 0, "caja\nmate-screensaver>=1.28\n", "")
            self.assertEqual(args, ("apk", "add", "--no-network", "caja"))
            return subprocess.CompletedProcess(args, 1, "", "cannot preserve components")
        with patch.object(remove, "run", side_effect=command):
            with self.assertRaises(subprocess.CalledProcessError):
                remove.alpine_components()

    def test_required_dpkg_locker_is_retained_without_forced_removal(self):
        def command(*args):
            if args[0] == "dpkg-query":
                return subprocess.CompletedProcess(args, 0, "installed", "")
            self.assertEqual(args, ("dpkg", "--simulate", "--purge", "mate-screensaver"))
            return subprocess.CompletedProcess(args, 1, "", "required by desktop")
        with patch.object(remove, "PACKAGES", ("mate-screensaver",)), \
                patch.object(remove.shutil, "which", side_effect=lambda name: name if name == "dpkg" else None), \
                patch.object(remove, "run", side_effect=command):
            remove.main()

    def test_dependency_on_optional_lxlock_is_removed_before_retrying_locker(self):
        installed = {"light-locker", "lxlock"}
        def command(*args):
            package = args[-1]
            if args[0] == "dpkg-query":
                return subprocess.CompletedProcess(args, 0, "installed" if package in installed else "", "")
            if "--simulate" in args:
                return subprocess.CompletedProcess(args, int(package == "light-locker" and "lxlock" in installed), "", "")
            self.assertEqual(args[:2], ("dpkg", "--purge"))
            installed.remove(package)
            return subprocess.CompletedProcess(args, 0, "", "")
        with patch.object(remove, "PACKAGES", ("light-locker", "lxlock")), \
                patch.object(remove.shutil, "which", side_effect=lambda name: name if name == "dpkg" else None), \
                patch.object(remove, "run", side_effect=command):
            remove.main()
        self.assertEqual(installed, set())

    def test_failed_real_removal_is_reported(self):
        results = [subprocess.CompletedProcess([], 0, "installed", ""),
                   subprocess.CompletedProcess([], 0, "", ""),
                   subprocess.CompletedProcess([], 1, "", "disk failure")]
        with patch.object(remove, "PACKAGES", ("mate-screensaver",)), \
                patch.object(remove.shutil, "which", side_effect=lambda name: name if name == "dpkg" else None), \
                patch.object(remove, "run", side_effect=results):
            with self.assertRaisesRegex(RuntimeError, "disk failure"):
                remove.main()


@unittest.skipUnless(os.name == "posix", "Desktop sessions run inside Linux containers")
class RequiredScreensaverTests(unittest.TestCase):
    def test_required_binary_is_disabled_and_unrelated_autostart_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root / "usr/bin/xscreensaver"
            binary.parent.mkdir(parents=True)
            binary.write_text("#!/bin/sh\nexit 0\n")
            binary.chmod(0o755)
            autostart = root / "etc/xdg/autostart"
            autostart.mkdir(parents=True)
            (autostart / "lxqt-xscreensaver-autostart.desktop").touch()
            (autostart / "panel.desktop").touch()
            remove.disable_required_xscreensaver(root)
            self.assertTrue(binary.exists())
            self.assertEqual(binary.stat().st_mode & 0o111, 0)
            self.assertFalse((autostart / "lxqt-xscreensaver-autostart.desktop").exists())
            self.assertTrue((autostart / "panel.desktop").exists())


@unittest.skipUnless(os.name == "posix", "Desktop sessions run inside Linux containers")
class CinnamonSessionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name, body in {
                "gsettings": 'exit "${SETTINGS_EXIT:-0}"',
                "xset": 'exit 0',
                "cinnamon-session": 'printf "desktop-started\\n"; exit 7'}.items():
            path = self.root / name
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"])

    def run_session(self):
        return subprocess.run(["/bin/sh", str(ROOT / "docker/config/session/start-cinnamon-unlocked.sh")],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_policy_failure_prevents_unprotected_desktop_start(self):
        self.env["SETTINGS_EXIT"] = "9"
        result = self.run_session()
        self.assertEqual(result.returncode, 9)
        self.assertEqual(result.stdout, "")

    def test_desktop_exit_status_is_preserved(self):
        result = self.run_session()
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(result.stdout, "desktop-started\n")

    def test_desktop_starts_without_optional_xset_utility(self):
        (self.root / "xset").unlink()
        self.env["PATH"] = str(self.root)
        result = self.run_session()
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(result.stdout, "desktop-started\n")


if __name__ == "__main__":
    unittest.main()
