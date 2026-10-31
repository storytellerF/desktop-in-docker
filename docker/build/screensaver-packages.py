"""Install Alpine desktop components without optional standalone lockers.

The MATE/LXQt metapackages require a locker. Install their actual dependency
lists instead of the metapackage, preserving all other desktop components.
"""

import re
import subprocess
import sys


LOCKERS = {"mate-screensaver", "xfce4-screensaver", "xscreensaver",
           "gnome-screensaver", "light-locker", "lxlock", "i3lock", "xtrlock"}
METAPACKAGES = {"mate-desktop-environment", "lxqt-desktop"}


def components(text):
    dependencies = [line.strip() for line in text.splitlines() if line.strip()]
    if not dependencies or any(not re.fullmatch(r"[\w.+:!<>=~@-]+", dep)
                               for dep in dependencies):
        raise ValueError("Invalid or empty Alpine desktop dependency list")
    result = [dep for dep in dependencies if re.split(r"[<>=~]", dep)[0] not in LOCKERS]
    if not result:
        raise ValueError("Desktop dependency list contains no desktop components")
    return result


def main(args):
    if not args or args[0] not in METAPACKAGES:
        raise ValueError("Expected a supported Alpine desktop metapackage")
    subprocess.run(["apk", "update"], check=True)
    metadata = subprocess.run(["apk", "-q", "info", "-R", args[0]],
                              check=True, capture_output=True, text=True).stdout
    subprocess.run(["apk", "add", "--no-cache", *components(metadata), *args[1:],
                    *["!" + name for name in sorted(LOCKERS)]], check=True)


if __name__ == "__main__":
    main(sys.argv[1:])
