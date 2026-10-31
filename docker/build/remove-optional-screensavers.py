"""Remove optional lockers already installed by desktop dependencies or parents.

Never force removal through a desktop dependency or autoremove other packages.
Retained packages are reported so runtime checks can identify necessary exceptions.
"""

import re
from pathlib import Path
import shutil
import subprocess


PACKAGES = ("lxlock", "light-locker-settings", "light-locker", "mate-screensaver", "xfce4-screensaver",
            "gnome-screensaver", "xscreensaver", "xscreensaver-gl-base", "xscreensaver-base", "i3lock", "xtrlock")


def run(*args):
    return subprocess.run(args, text=True, capture_output=True)


def alpine_components():
    # Keep every non-locker component anchored before removing a metapackage:
    # apk del would otherwise also remove its automatically installed desktop.
    for meta in ("mate-desktop-environment", "lxqt-desktop"):
        if run("apk", "info", "-e", meta).returncode:
            continue
        result = run("apk", "-q", "info", "-R", meta)
        result.check_returncode()
        dependencies = result.stdout.split()
        keep = [dep for dep in dependencies if re.split(r"[<>=~]", dep)[0] not in PACKAGES]
        if not keep:
            raise ValueError(f"Empty desktop component list for {meta}")
        run("apk", "add", "--no-network", *keep).check_returncode()
        run("apk", "del", "--no-network", meta).check_returncode()


def disable_required_xscreensaver(root=Path("/")):
    # Fedora LXQt's panel requires xscreensaver-base, and its autostart daemon
    # still locks the container after optional packages have been removed.
    binary = root / "usr/bin/xscreensaver"
    if binary.exists():
        binary.chmod(binary.stat().st_mode & ~0o111)
        for name in ("xscreensaver.desktop", "xscreensaver-autostart.desktop",
                     "lxqt-xscreensaver-autostart.desktop"):
            (root / "etc/xdg/autostart" / name).unlink(missing_ok=True)


def main():
    if shutil.which("apk"):
        alpine_components()
    remaining = list(PACKAGES)
    while remaining:
        removed = []
        for package in remaining:
            if shutil.which("dpkg"):
                if run("dpkg-query", "-W", "-f=${db:Status-Status}", package).stdout != "installed":
                    continue
                check = run("dpkg", "--simulate", "--purge", package)
                command = ("dpkg", "--purge", package)
            elif shutil.which("rpm"):
                if run("rpm", "-q", package).returncode:
                    continue
                check = run("rpm", "-e", "--test", package)
                command = ("rpm", "-e", package)
            elif shutil.which("apk"):
                if run("apk", "info", "-e", package).returncode:
                    continue
                check = run("apk", "-q", "info", "-r", package)
                check.check_returncode()
                if check.stdout.strip():
                    print(f"Retaining required package: {package}")
                    continue
                command = ("apk", "del", "--no-network", package)
            elif shutil.which("pacman"):
                if run("pacman", "-Q", package).returncode:
                    continue
                check = run("pacman", "-R", "--print", package)
                command = ("pacman", "-R", "--noconfirm", package)
            else:
                raise RuntimeError("Unsupported desktop package manager")
            if check.returncode:
                print(f"Retaining required package: {package}")
                continue
            result = run(*command)
            print(result.stdout, end="")
            if result.returncode:
                raise RuntimeError(result.stderr)
            removed.append(package)
        if not removed:
            break
        remaining = [package for package in remaining if package not in removed]
    disable_required_xscreensaver()


if __name__ == "__main__":
    main()
