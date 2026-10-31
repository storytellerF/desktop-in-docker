"""Only lock-related fields change in Enlightenment's native configuration."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


PATH = Path(__file__).resolve().parents[1] / "docker/config/session/enlightenment-no-lock.py"
SPEC = importlib.util.spec_from_file_location("enlightenment_no_lock", PATH)
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


class EnlightenmentLockConfigTests(unittest.TestCase):
    def test_personal_authentication_cannot_reuse_an_existing_password(self):
        text = ('group "E_Config" struct {\n'
                '    value "desklock_auth_method" int: 0;\n'
                '    value "desklock_passwd" int: 12345;\n'
                '    value "theme" string: "desk_lock";\n}\n')
        result = policy.configure(text, True)
        self.assertIn('value "desklock_auth_method" int: 1;', result)
        self.assertIn('value "desklock_passwd" int: 0;', result)
        self.assertIn('value "theme" string: "desk_lock";', result)

    def test_unrelated_bindings_remain_unchanged(self):
        text = ('group "E_Config_Bindings" struct {\n'
                '    value "action" string: "desk_lock";\n'
                '    value "action" string: "desk_show";\n}\n')
        self.assertEqual(policy.configure(text, False), text.replace('"desk_lock"', '""'))

    def test_repeated_configuration_does_not_duplicate_default_fields(self):
        first = policy.configure('group "E_Config" struct {\n}\n', True)
        self.assertEqual(policy.configure(first, True), first)
        self.assertEqual(first.count('value "screensaver_enable"'), 1)

    def test_invalid_configuration_fails_without_silently_keeping_locking(self):
        for text in ('invalid', 'group "E_Config" struct {value "desklock_passwd" string: "bad";}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                policy.configure(text, True)

    @unittest.skipUnless(os.name == "posix", "Profile readability uses Unix file modes")
    def test_eet_rewrite_preserves_readability_of_system_profiles(self):
        class Eet:
            def eet_open(self, path, mode):
                self.path = Path(os.fsdecode(path))
                return 1

            def eet_data_dump(self, handle, key, callback, context):
                callback(None, b'group "E_Config" struct {\n}\n')
                return 1

            def eet_data_undump(self, *args):
                return 1

            def eet_close(self, handle):
                self.path.chmod(0o600)
                return 0

        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "e.cfg"
            path.write_bytes(b"native profile")
            path.chmod(0o644)
            policy.update(Eet(), path)
            self.assertEqual(path.stat().st_mode & 0o777, 0o644)


if __name__ == "__main__":
    unittest.main()
