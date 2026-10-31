"""Webtop idle policy uses the existing X11 API and releases its connection."""

import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import Mock, patch


PATH = Path(__file__).resolve().parents[1] / "docker/config/session/disable-x11-idle.py"
SPEC = importlib.util.spec_from_file_location("disable_x11_idle", PATH)
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


class X11IdleTests(unittest.TestCase):
    def setUp(self):
        self.lib = Mock()
        self.lib.XOpenDisplay.return_value = 123
        library = patch.object(policy.c, "CDLL", return_value=self.lib)
        library.start()
        self.addCleanup(library.stop)
        environment = patch.dict(os.environ, DISPLAY=":99")
        environment.start()
        self.addCleanup(environment.stop)

    def test_timeout_is_zero_and_request_is_flushed(self):
        policy.main()
        self.lib.XSetScreenSaver.assert_called_once_with(123, 0, 0, 0, 1)
        self.lib.XSync.assert_called_once_with(123, 0)
        self.lib.XCloseDisplay.assert_called_once_with(123)

    def test_failed_display_connection_does_not_call_x11_with_null_handle(self):
        self.lib.XOpenDisplay.return_value = None
        with self.assertRaisesRegex(RuntimeError, "Cannot open"):
            policy.main()
        self.lib.XSetScreenSaver.assert_not_called()
        self.lib.XCloseDisplay.assert_not_called()

    def test_connection_closes_even_if_setting_timeout_fails(self):
        self.lib.XSetScreenSaver.side_effect = RuntimeError("X server unavailable")
        with self.assertRaisesRegex(RuntimeError, "X server unavailable"):
            policy.main()
        self.lib.XCloseDisplay.assert_called_once_with(123)


if __name__ == "__main__":
    unittest.main()
