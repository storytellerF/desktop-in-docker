"""Disable the X server's own idle blanking in an upstream Webtop session."""

import ctypes as c
import os


def main():
    lib = c.CDLL("libX11.so.6")
    lib.XOpenDisplay.argtypes, lib.XOpenDisplay.restype = [c.c_char_p], c.c_void_p
    lib.XSetScreenSaver.argtypes = [c.c_void_p, c.c_int, c.c_int, c.c_int, c.c_int]
    lib.XSync.argtypes = [c.c_void_p, c.c_int]
    lib.XCloseDisplay.argtypes = [c.c_void_p]
    display = lib.XOpenDisplay(os.environ["DISPLAY"].encode())
    if not display:
        raise RuntimeError("Cannot open the desktop display to disable idle blanking")
    try:
        lib.XSetScreenSaver(display, 0, 0, 0, 1)
        lib.XSync(display, 0)
    finally:
        lib.XCloseDisplay(display)


if __name__ == "__main__":
    main()
