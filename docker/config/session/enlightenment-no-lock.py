"""Disable Enlightenment's integrated locker using its native Eet configuration.

E's personal-password mode refuses to lock when no password is configured.
This also prevents menu/API requests from trapping the passwordless container.
Keep the locker module loaded: removing it can leave an input-blocking screen.
"""

import ctypes as c
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


SETTINGS = {"screensaver_enable": 0, "desklock_start_locked": 0,
            "desklock_on_suspend": 0, "desklock_autolock_screensaver": 0,
            "desklock_auth_method": 1, "desklock_passwd": 0, "desklock_pin": 0}


def configure(text, main_config):
    if main_config:
        for name, value in SETTINGS.items():
            pattern = rf'(value "{name}" int: )-?\d+(;)'
            text, count = re.subn(pattern, lambda m: m[1] + str(value) + m[2], text)
            if not count:
                if re.search(rf'value "{name}"\s', text):
                    raise ValueError(f"Unsupported type for Enlightenment setting: {name}")
                header = re.search(r'group "[^"]+" struct \{', text)
                if not header:
                    raise ValueError("Invalid Enlightenment configuration group")
                text = text[:header.end()] + f'\n    value "{name}" int: {value};' + text[header.end():]
    return re.sub(r'(value "action" string: )"desk_lock"(;)', r'\1""\2', text)


def update(lib, path):
    callback_type = c.CFUNCTYPE(None, c.c_void_p, c.c_char_p)
    with tempfile.TemporaryDirectory(dir=path.parent) as temp:
        pending = Path(temp) / path.name
        shutil.copy2(path, pending)
        handle = lib.eet_open(os.fsencode(pending), 2)  # READ_WRITE preserves other entries.
        if not handle:
            raise RuntimeError(f"Cannot open Eet configuration: {path}")
        try:
            chunks = []
            callback = callback_type(lambda _, data: chunks.append(data))
            if not lib.eet_data_dump(handle, b"config", callback, None):
                raise RuntimeError(f"Cannot decode Eet configuration: {path}")
            before = b"".join(chunks).decode("utf-8")
            after = configure(before, path.name == "e.cfg")
            if after != before:
                encoded = after.encode("utf-8")
                if not lib.eet_data_undump(handle, b"config", encoded, len(encoded), 1):
                    raise RuntimeError(f"Cannot encode Eet configuration: {path}")
        finally:
            error = lib.eet_close(handle)
        if error:
            raise RuntimeError(f"Cannot save Eet configuration: {path}")
        if after != before:
            # Eet rewrites files with mode 0600, including public system profiles.
            shutil.copystat(path, pending)
            os.replace(pending, path)


def main(paths):
    lib = c.CDLL("libeet.so.1")
    lib.eet_open.argtypes, lib.eet_open.restype = [c.c_char_p, c.c_int], c.c_void_p
    lib.eet_close.argtypes = [c.c_void_p]
    lib.eet_data_dump.argtypes = [c.c_void_p, c.c_char_p, c.c_void_p, c.c_void_p]
    lib.eet_data_undump.argtypes = [c.c_void_p, c.c_char_p, c.c_char_p, c.c_int, c.c_int]
    if lib.eet_init() <= 0:
        raise RuntimeError("Cannot initialize Eet")
    try:
        for directory in map(Path, paths):
            for name in ("e.cfg", "e_bindings.cfg"):
                for path in directory.rglob(name):
                    update(lib, path)
    finally:
        lib.eet_shutdown()


if __name__ == "__main__":
    main(sys.argv[1:])
