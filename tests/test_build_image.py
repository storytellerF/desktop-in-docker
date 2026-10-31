"""Contract tests execute the real build entry point with an offline Docker process."""

from contextlib import redirect_stderr, redirect_stdout
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import io
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_image", REPO / "scripts/build_image.py")
build_image = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = build_image
SPEC.loader.exec_module(build_image)
DESKTOPS = ("xfce", "lxqt", "kde", "mate", "cinnamon", "lxde", "gnome", "enlightenment")
WEBTOP_DESKTOPS = {"debian": ("xfce", "kde", "mate"),
                   "ubuntu": ("xfce", "lxqt", "kde", "mate"),
                   "fedora": ("xfce", "kde", "mate"),
                   "arch": ("xfce", "kde", "mate"),
                   "alpine": ("kde",)}
VERSIONS = {"debian": "trixie", "ubuntu": "noble", "fedora": "41", "alpine": "latest", "arch": "latest"}


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="desktop-in-docker-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(REPO / "docker", self.root / "docker")
        shutil.copy(REPO / "docker-compose.yml", self.root)
        self.log = self.root / "docker.jsonl"
        self.env = {key: value for key, value in os.environ.items()
                    if key not in {"SYSTEM", "SYSTEM_VERSION", "DESKTOP_ENV", "IMAGE_VARIANT",
                                   "DOCKER_USERNAME", "VNC_PASSWD", "CN_MIRROR_MODE", "ENABLE_CN_MIRROR", "RDP_PORT"}
                    and not key.startswith("FAKE_DOCKER_")}
        self.env.update(TZ="UTC", FAKE_DOCKER_LOG=str(self.log))

    def run_build(self, *args, status=0, inputs=()):
        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output), patch("builtins.input", side_effect=inputs):
            actual = build_image.main(list(args), root=self.root, environ=self.env,
                                      docker_command=(sys.executable, str(REPO / "tests/fakes/docker.py")))
        self.assertEqual(actual, status, output.getvalue())
        self.output = output.getvalue()
        return [json.loads(line) for line in self.log.read_text(encoding="utf-8").splitlines()] if self.log.exists() else []

    def check_build(self, variant, system, desktop, cn):
        calls = self.run_build("-i", variant, "-s", system, "-d", desktop, "-b",
                               "--cn-mirror" if cn else "--no-cn-mirror")
        commands = [call["argv"] for call in calls]
        self.assertFalse(any(command[:2] == ["image", "prune"] for command in commands))
        builds = commands
        self.assertEqual(len(builds), 1 if variant == "webtop" else 2)
        merged = builds[0][-2]
        self.assertRegex(merged, rf"^build/{variant}/[0-9a-f]{{32}}/{system}{'_cn' if cn else ''}\.Dockerfile$")
        self.assertEqual(builds[0][-3:], ["-f", merged, "."])
        content = (self.root / merged).read_text(encoding="utf-8")
        self.assertIn("FROM ${", content)
        self.assertIn("# Source: docker/dockerfiles/", content)
        if cn:
            family = "webtop" if variant == "webtop" else "base"
            mirror_system = "debian" if system == "ubuntu" else system
            fragment = f"docker/dockerfiles/fragments/{family}/cn/{mirror_system}_cn.dockerfrag"
            fragment_text = (self.root / fragment).read_text(encoding="utf-8")
            self.assertIn(fragment_text, content)
            # The original dependency section must remain after all injected text.
            if variant == "webtop":
                source = f"docker/dockerfiles/webtop/{system}.Dockerfile"
            elif variant == "wayland":
                source = "docker/dockerfiles/wayland/base/arch.Dockerfile"
            else:
                source = f"docker/dockerfiles/base/{system}.Dockerfile"
            if not (self.root / source).exists():
                source = f"docker/dockerfiles/{'webtop' if variant == 'webtop' else 'base'}/debian.Dockerfile"
            dependencies = (self.root / source).read_text(encoding="utf-8").split(build_image.MARKER, 1)[1].lstrip()
            self.assertLess(content.index(fragment_text), content.index(dependencies))
        if variant == "webtop":
            self.assertIn(f"WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:{system}-{desktop}", builds[0])
            self.assertFalse(any(arg.startswith("BASE_IMAGE=") for arg in builds[0]))
            self.assertIn("# Source: docker/dockerfiles/fragments/webtop/config.dockerfrag", content)
        else:
            user = "user" if system == "fedora" else system
            version = ({"kde": "3.21", "gnome": "3.22", "cinnamon": "edge", "enlightenment": "edge"}
                       .get(desktop, "latest") if system == "alpine" and variant == "x11" else VERSIONS[system])
            self.assertEqual(builds[0][:11], [
                "build", "--build-arg", f"BASE_FROM_IMAGE={'archlinux' if system == 'arch' else system}:{version}",
                "--build-arg", f"SYSTEM={system}", "--build-arg", f"SYSTEM_VERSION={version}",
                "--build-arg", f"USERNAME={user}", "--build-arg", "TIMEZONE=UTC"])
            expected = f"docker/dockerfiles/{variant}/{desktop}/{system}.Dockerfile"
            if not (self.root / expected).is_file():
                expected = f"docker/dockerfiles/{variant}/{desktop}/debian.Dockerfile"
            if variant == "x11":
                prepared = str(Path(merged).with_name("desktop.Dockerfile")).replace("\\", "/")
                self.assertEqual(builds[1][-3:], ["-f", prepared, "."])
                desktop_content = (self.root / prepared).read_text()
                self.assertTrue(desktop_content.startswith(f"# Source: {expected}\n"))
                self.assertIn("remove-screensavers.dockerfrag", desktop_content)
                self.assertEqual("cinnamon-no-lock.dockerfrag" in desktop_content, desktop == "cinnamon")
                self.assertEqual("enlightenment-no-lock.dockerfrag" in desktop_content, desktop == "enlightenment")
                self.assertEqual("kde-no-lock.dockerfrag" in desktop_content, desktop == "kde")
                self.assertEqual("mate-no-lock.dockerfrag" in desktop_content, desktop == "mate")
                self.assertEqual("fedora-xfce-no-idle.dockerfrag" in desktop_content,
                                 desktop == "xfce" and system == "fedora")
            else:
                self.assertEqual(builds[1][-3:], ["-f", expected, "."])
            base_tag = builds[0][builds[0].index("-t") + 1]
            self.assertIn(f"BASE_IMAGE={base_tag}", builds[1])
            if variant == "x11":
                self.assertIn("# Source: docker/dockerfiles/fragments/custom/user-config.dockerfrag", content)
                self.assertEqual("# Source: docker/dockerfiles/fragments/custom/fcitx-config.dockerfrag" in content, cn)
                if system == "alpine":
                    self.assertIn("COPY base-scripts/start-desktop-session.sh "
                                  "/usr/local/bin/desktop-in-docker-session", content)
                    self.assertIn("/usr/share/xsessions/desktop-in-docker.desktop", content)
        for command in builds:
            self.assertEqual(command[0], "build")
            image_tags = [command[index + 1] for index, arg in enumerate(command) if arg == "-t"]
            self.assertTrue(any(tag.endswith("-snapshot") or tag.endswith(":snapshot") for tag in image_tags))
            self.assertEqual(any("-cn-" in tag or ":cn-" in tag for tag in image_tags), cn)

    def test_webtop_env_combination_rejected_before_docker(self):
        (self.root / ".env").write_text("IMAGE_VARIANT=webtop\nSYSTEM=debian\nDESKTOP_ENV=gnome\n")
        self.assertEqual(self.run_build("-b", status=1), [])
        self.assertIn("webtop does not support debian/gnome", self.output)
        self.assertFalse((self.root / "build").exists())

    def test_webtop_unsupported_start_rejected_before_docker(self):
        self.assertEqual(self.run_build("-i", "webtop", "-s", "alpine", "-S", status=1), [])
        self.assertIn("supported desktops: kde", self.output)
        self.assertNotIn("kde, mate", self.output)

    def test_webtop_unsupported_publish_rejected_before_docker(self):
        self.assertEqual(self.run_build("-i", "webtop", "-s", "arch", "-d", "lxqt", "-P", status=1), [])
        self.assertIn("webtop does not support arch/lxqt", self.output)

    def test_create_env_preserves_unrelated_settings_and_literal_password(self):
        (self.root / ".env").write_text('# Keep this\nSYSTEM="fedora"\nVNC_PASSWD="old"\n', encoding="utf-8")
        calls = self.run_build("-c", inputs=('a$&|"\\ secret', "example"))
        self.assertEqual(calls, [])
        values = build_image.load_env(self.root / ".env")
        self.assertEqual(values["VNC_PASSWD"], 'a$&|"\\ secret')
        self.assertEqual(values["DOCKER_USERNAME"], "example")
        self.assertEqual(values["SYSTEM"], "fedora")
        self.assertIn("# Keep this", (self.root / ".env").read_text())
        self.assertNotIn(values["VNC_PASSWD"], self.output)

    def test_cli_overrides_env_and_env_overrides_process_settings(self):
        self.env.update(SYSTEM="alpine", DESKTOP_ENV="mate")
        (self.root / ".env").write_text('SYSTEM="fedora"\nDESKTOP_ENV="kde"\n', encoding="utf-8")
        calls = self.run_build("-b", "-d", "lxqt")
        self.assertIn("SYSTEM=fedora", calls[0]["argv"])
        self.assertIn("DESKTOP_ENV=lxqt", calls[1]["argv"])

    def test_env_does_not_execute_shell_commands(self):
        (self.root / ".env").write_text('VNC_PASSWD=$(touch executed)\n', encoding="utf-8")
        self.assertEqual(self.run_build(), [])
        self.assertFalse((self.root / "executed").exists())

    def test_stop_precedes_start(self):
        calls = self.run_build("-T", "-S")
        self.assertEqual(calls[0]["argv"], ["compose", "-f", "docker-compose.yml", "down"])
        self.assertEqual(calls[1]["argv"], ["compose", "-f", "docker-compose.yml", "up", "-d", "--build"])

    def test_stop_only(self):
        self.assertEqual([c["argv"] for c in self.run_build("-T")], [["compose", "-f", "docker-compose.yml", "down"]])

    def test_stop_ignores_unsupported_cli_desktop_combination(self):
        calls = self.run_build("-T", "-i", "webtop", "-s", "alpine")
        self.assertEqual([c["argv"] for c in calls], [["compose", "-f", "docker-compose.yml", "down"]])
        self.assertFalse((self.root / "build").exists())

    def test_stop_ignores_unsupported_env_desktop_combination(self):
        (self.root / ".env").write_text("IMAGE_VARIANT=webtop\nSYSTEM=alpine\nDESKTOP_ENV=xfce\n")
        calls = self.run_build("-T")
        self.assertEqual([c["argv"] for c in calls], [["compose", "-f", "docker-compose.yml", "down"]])

    def test_invalid_restart_does_not_stop_existing_desktop(self):
        self.assertEqual(self.run_build("-T", "-S", "-i", "webtop", "-s", "alpine", status=1), [])

    def test_stop_only_propagates_docker_failure(self):
        self.env.update(FAKE_DOCKER_FAIL_COMMANDS="compose-down", FAKE_DOCKER_FAIL_EXIT_CODE="7")
        self.assertEqual(len(self.run_build("-T", "-i", "webtop", "-s", "alpine", status=7)), 1)

    def test_parallel_preparation_keeps_each_desktop_dockerfile(self):
        combinations = (("alpine", "kde"), ("debian", "kde"), ("debian", "mate")) * 6
        def prepare(combination):
            system, desktop = combination
            args = build_image.parser().parse_args(["-i", "webtop", "-s", system, "-d", desktop])
            config = build_image.Config.from_args(args, {"TZ": "UTC"})
            return build_image.prepare(self.root, config)[1]
        with ThreadPoolExecutor(max_workers=8) as pool:
            paths = list(pool.map(prepare, combinations))
        self.assertEqual(len(set(paths)), len(paths))
        for combination, path in zip(combinations, paths):
            self.assertEqual("session-process-limits.sh" in (self.root / path).read_text(),
                             combination == ("alpine", "kde"))

    def test_start_latest_cn_configuration(self):
        calls = self.run_build("-S", "--latest", "--cn-mirror")
        env = calls[0]["env"]
        self.assertEqual(env["IMAGE_TAG"], "debian-trixie-xfce-cn-latest")
        self.assertEqual(env["CONTAINER_HOME"], "/home/debian")

    def test_custom_rdp_port(self):
        self.env["RDP_PORT"] = "3390"
        calls = self.run_build("-S", "-i", "wayland", "-s", "arch")
        self.assertEqual(calls[-1]["argv"], ["compose", "port", "desktop", "3390"])
        self.assertEqual(calls[0]["env"]["CONTAINER_RDP_PORT"], "3390")

    def test_missing_fragment_fails_before_docker(self):
        (self.root / "docker/dockerfiles/fragments/custom/user-config.dockerfrag").unlink()
        self.assertEqual(self.run_build("-b", status=1), [])

    def test_missing_marker_fails_before_docker(self):
        source = self.root / "docker/dockerfiles/base/debian.Dockerfile"
        source.write_text(source.read_text().replace(build_image.MARKER, "removed"))
        self.assertEqual(self.run_build("-b", status=1), [])

    def test_default_shorthand_tags_and_no_snapshot(self):
        calls = self.run_build("-b", "--latest", "--no-snapshot")
        base, desktop = calls[0]["argv"], calls[1]["argv"]
        self.assertIn("desktop-in-docker:base-latest", base)
        self.assertIn("desktop-in-docker:latest", desktop)
        self.assertFalse(any("snapshot" in arg for call in calls for arg in call["argv"]))

    def test_port_query_failure_reports_missing_mapping(self):
        self.env["FAKE_DOCKER_FAIL_COMMANDS"] = "compose-port"
        self.run_build("-S")
        self.assertIn("Port mapping not found", self.output)

    def test_cli_help(self):
        script = REPO / "scripts/build_image.py"
        result = subprocess.run([sys.executable, str(script), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)

    def test_cli_missing_value(self):
        script = REPO / "scripts/build_image.py"
        result = subprocess.run([sys.executable, str(script), "--system"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_env_quoted_value_with_comment(self):
        (self.root / ".env").write_text('SYSTEM="fedora" # distro\n', encoding="utf-8")
        calls = self.run_build("-b")
        self.assertIn("SYSTEM=fedora", calls[0]["argv"])

    def test_explicit_alpine_version_overrides_desktop_default(self):
        calls = self.run_build("-b", "-s", "alpine", "-d", "gnome", "-v", "3.21")
        self.assertIn("BASE_FROM_IMAGE=alpine:3.21", calls[0]["argv"])
        self.assertIn("SYSTEM_VERSION=3.21", calls[0]["argv"])

    def test_env_alpine_version_overrides_desktop_default(self):
        (self.root / ".env").write_text("SYSTEM_VERSION=3.21\n", encoding="utf-8")
        calls = self.run_build("-b", "-s", "alpine", "-d", "gnome")
        self.assertIn("BASE_FROM_IMAGE=alpine:3.21", calls[0]["argv"])

    def test_alpine_webtop_kde_installs_process_limit_environment(self):
        calls = self.run_build("-b", "-i", "webtop", "-s", "alpine", "-d", "kde")
        dockerfile = (self.root / calls[0]["argv"][-2]).read_text()
        self.assertIn("COPY base-scripts/session-process-limits.sh "
                      "/etc/xdg/plasma-workspace/env/desktop-in-docker-process-limits.sh", dockerfile)

    def test_other_webtop_desktops_keep_upstream_process_limits(self):
        calls = self.run_build("-b", "-i", "webtop", "-s", "debian", "-d", "mate")
        dockerfile = (self.root / calls[0]["argv"][-2]).read_text()
        self.assertNotIn("session-process-limits.sh", dockerfile)

    def test_edge_repository_normalization_precedes_cn_bootstrap(self):
        calls = self.run_build("-b", "-s", "alpine", "-d", "cinnamon", "--cn-mirror")
        dockerfile = (self.root / calls[0]["argv"][-2]).read_text()
        self.assertLess(dockerfile.index("https://cdn.alpinelinux.org/"),
                        dockerfile.index("RUN apk add --no-cache curl ca-certificates bash"))

    def test_env_regression_unknown_double_quoted_escape(self):
        (self.root / ".env").write_text('VNC_PASSWD="abc\\q"\n', encoding="utf-8")
        calls = self.run_build("-b")
        self.assertEqual(build_image.load_env(self.root / ".env")["VNC_PASSWD"], r"abc\q")
        self.assertEqual(calls[0]["argv"][0], "build")

    def test_env_regression_single_quoted_value_with_comment(self):
        (self.root / ".env").write_text("SYSTEM='fedora' # distro\n", encoding="utf-8")
        calls = self.run_build("-b")
        self.assertIn("SYSTEM=fedora", calls[0]["argv"])

    def test_env_quoted_literal_values(self):
        cases = (
            ('"" # empty', ""),
            ("'' # empty", ""),
            ('"a # b" # comment', "a # b"),
            ("'a # b' # comment", "a # b"),
            ('"a\\q\\z"', r"a\q\z"),
            ('"a\\\\q"', r"a\q"),
            ('"a\\\"b" # comment', 'a"b'),
            ('"a\\n\\t\\r"', "a\n\t\r"),
            ('"\\u0001"', "\x01"),
            ('"\\ud83d\\ude00"', "\U0001f600"),
            ("'a\\n\\t' # comment", r"a\n\t"),
            ("'abc\\' # comment", "abc\\"),
            ('"$HOME $(echo test)"', "$HOME $(echo test)"),
        )
        path = self.root / ".env"
        for encoded, expected in cases:
            with self.subTest(encoded=encoded):
                path.write_text(f"VNC_PASSWD={encoded}\n", encoding="utf-8")
                self.assertEqual(build_image.load_env(path)["VNC_PASSWD"], expected)

    def test_env_rejects_unclosed_quotes_and_trailing_text(self):
        path = self.root / ".env"
        for value in ('"unclosed', "'unclosed", '"fedora" extra', "'fedora' extra"):
            with self.subTest(value=value):
                path.write_text(f"SYSTEM={value}\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "line 1"):
                    build_image.load_env(path)

    def test_unknown_mirror_mode_rejected_before_docker(self):
        self.env["CN_MIRROR_MODE"] = "typo"
        self.assertEqual(self.run_build("-b", status=1), [])

    def test_interactive_random_password_is_saved(self):
        self.run_build("-c", inputs=("r", ""))
        password = build_image.load_env(self.root / ".env")["VNC_PASSWD"]
        self.assertEqual(len(password), 16)
        self.assertTrue(password.isalnum())
        self.assertNotIn(password, self.output)

    def test_named_registry_is_used_for_tags_and_base_reference(self):
        self.env["DOCKER_USERNAME"] = "example"
        calls = self.run_build("-b")
        base = calls[0]["argv"]
        base_tag = base[base.index("-t") + 1]
        self.assertTrue(base_tag.startswith("example/desktop-in-docker:"))
        self.assertIn(f"BASE_IMAGE={base_tag}", calls[1]["argv"])


for name, env, options, enabled in (
    ("china_timezone", {"TZ": "Asia/Shanghai"}, (), True),
    ("non_china_timezone", {"TZ": "UTC"}, (), False),
    ("legacy_enabled", {"ENABLE_CN_MIRROR": "true"}, (), True),
    ("explicit_off", {"TZ": "Asia/Shanghai"}, ("--no-cn-mirror",), False),
    ("cli_overrides_env", {"CN_MIRROR_MODE": "off"}, ("--cn-mirror",), True),
):
    def case(self, settings=env, args=options, expected=enabled):
        self.env.update(settings)
        calls = self.run_build("-S", *args)
        self.assertEqual("-cn-" in calls[0]["env"]["IMAGE_TAG"], expected)
    case.__name__ = f"test_mirror_{name}"
    setattr(BuildTests, case.__name__, case)


def add_matrix_test(name, function):
    function.__name__ = name
    setattr(BuildTests, name, function)


for variant, systems in (("x11", ("debian", "ubuntu", "fedora", "alpine")),
                         ("webtop", ("debian", "ubuntu", "fedora", "arch", "alpine")),
                         ("wayland", ("arch",))):
    desktops = ("weston",) if variant == "wayland" else DESKTOPS
    for system, desktop, cn in itertools.product(systems, desktops, (False, True)):
        if system == "alpine" and desktop == "mate":
            def case(self, v=variant, mirror=cn):
                calls = self.run_build("-i", v, "-s", "alpine", "-d", "mate", "-b",
                                       "--cn-mirror" if mirror else "--no-cn-mirror", status=1)
                self.assertEqual(calls, [])
                self.assertIn(f"{v} does not support alpine/mate", self.output)
                self.assertFalse((self.root / "build").exists())
            add_matrix_test(f"test_reject_{variant}_alpine_mate_{'cn' if cn else 'global'}", case)
        elif variant == "webtop" and desktop not in WEBTOP_DESKTOPS[system]:
            def case(self, s=system, d=desktop, mirror=cn):
                calls = self.run_build("-i", "webtop", "-s", s, "-d", d, "-b",
                                       "--cn-mirror" if mirror else "--no-cn-mirror", status=1)
                self.assertEqual(calls, [])
                self.assertIn(f"webtop does not support {s}/{d}", self.output)
                self.assertFalse((self.root / "build").exists())
            add_matrix_test(f"test_reject_webtop_{system}_{desktop}_{'cn' if cn else 'global'}", case)
        else:
            def case(self, v=variant, s=system, d=desktop, mirror=cn):
                self.check_build(v, s, d, mirror)
            add_matrix_test(f"test_build_{variant}_{system}_{desktop}_{'cn' if cn else 'global'}", case)

for variant in ("x11", "webtop"):
    for action, options in (("build", ("-b",)), ("start", ("-S",)),
                            ("publish", ("-P",)), ("restart", ("-T", "-S"))):
        def case(self, v=variant, args=options):
            self.assertEqual(self.run_build("-i", v, "-s", "alpine", "-d", "mate", *args, status=1), [])
            self.assertIn("this combination is disabled", self.output)
            self.assertFalse((self.root / "build").exists())
        add_matrix_test(f"test_disabled_alpine_mate_{variant}_{action}_before_docker", case)

    for source in ("process_env", "dotenv"):
        def case(self, v=variant, settings_source=source):
            values = dict(IMAGE_VARIANT=v, SYSTEM="alpine", DESKTOP_ENV="mate")
            if settings_source == "dotenv":
                (self.root / ".env").write_text("\n".join(f"{key}={value}" for key, value in values.items()))
            else:
                self.env.update(values)
            self.assertEqual(self.run_build("-b", status=1), [])
            self.assertIn(f"{v} does not support alpine/mate", self.output)
            self.assertFalse((self.root / "build").exists())
        add_matrix_test(f"test_disabled_alpine_mate_{variant}_from_{source}", case)

    def explicit_version(self, v=variant):
        self.assertEqual(self.run_build("-i", v, "-s", "alpine", "-d", "mate", "-v", "3.22", "-b", status=1), [])
        self.assertIn("this combination is disabled", self.output)
    add_matrix_test(f"test_disabled_alpine_mate_{variant}_explicit_version", explicit_version)

    def stop_disabled(self, v=variant):
        calls = self.run_build("-i", v, "-s", "alpine", "-d", "mate", "-T")
        self.assertEqual([call["argv"] for call in calls], [["compose", "-f", "docker-compose.yml", "down"]])
        self.assertFalse((self.root / "build").exists())
    add_matrix_test(f"test_disabled_alpine_mate_{variant}_can_still_stop", stop_disabled)


for name, args, message in (
    ("arch_x11", ("-s", "arch"), "x11 does not support --system arch"),
    ("ubuntu_version", ("-s", "ubuntu", "-v", "plucky"), "supports noble/24.04 or earlier only"),
    ("wayland_system", ("-i", "wayland", "-s", "debian"), "wayland supports --system arch only"),
    ("wayland_desktop", ("-i", "wayland", "-s", "arch", "-d", "xfce"), "wayland supports --desktop weston only"),
    ("system", ("-s", "unknown"), "Unsupported system"),
    ("desktop", ("-d", "../xfce"), "Unsupported desktop"),
    ("variant", ("-i", "unknown"), "Unknown image variant"),
):
    def case(self, options=args, expected=message):
        self.assertEqual(self.run_build("-b", *options, status=1), [])
        self.assertIn(expected, self.output)
    add_matrix_test(f"test_reject_{name}_before_docker", case)

for variant, system, ports, home in (("x11", "debian", ("6080", "5901"), "/home/debian"),
                                     ("webtop", "debian", ("3000", "3001"), "/config"),
                                     ("wayland", "arch", ("3389",), "/home/arch")):
    def case(self, v=variant, s=system, expected_ports=ports, expected_home=home):
        calls = self.run_build("-S", "-i", v, "-s", s)
        self.assertEqual([call["argv"] for call in calls],
                         [["compose", "-f", "docker-compose.yml", "up", "-d", "--build"]]
                         + [["compose", "port", "desktop", port] for port in expected_ports])
        self.assertEqual(calls[0]["env"]["CONTAINER_HOME"], expected_home)
        self.assertIn("localhost:", self.output)
    add_matrix_test(f"test_start_{variant}", case)

for variant, system in (("x11", "debian"), ("wayland", "arch"), ("webtop", "debian")):
    def case(self, v=variant, s=system):
        calls = self.run_build("-P", "-m", "-i", v, "-s", s)
        for call in calls:
            self.assertEqual(call["argv"][:4], ["buildx", "build", "--platform", "linux/amd64,linux/arm64"])
            self.assertIn("--push", call["argv"])
        self.assertEqual(len(calls), 1 if v == "webtop" else 2)
        self.assertFalse(any(call["argv"][:2] == ["image", "prune"] for call in calls))
    add_matrix_test(f"test_publish_{variant}", case)

for command, options, count in (("build", ("-b",), 1),
                                 ("buildx-build", ("-P",), 1),
                                 ("compose-up", ("-S",), 1),
                                 ("compose-down", ("-T", "-S"), 1)):
    def case(self, failure=command, args=options, expected_count=count):
        self.env.update(FAKE_DOCKER_FAIL_COMMANDS=failure, FAKE_DOCKER_FAIL_EXIT_CODE="7")
        calls = self.run_build(*args, status=7)
        self.assertEqual(len(calls), expected_count)
    add_matrix_test(f"test_propagate_{command.replace('-', '_')}_failure", case)


@unittest.skipUnless(os.name == "posix", "Plasma startup scripts run inside Linux containers")
class SessionProcessLimitTests(unittest.TestCase):
    def session_limit(self, initial_limit):
        # Change only the isolated child's limits; the test runner keeps its limits.
        code = """
import os
import resource
import sys
limit = int(sys.argv[1])
resource.setrlimit(resource.RLIMIT_NOFILE, (limit, limit))
os.execv("/bin/sh", ["sh", "-c", '. "$1"; ulimit -Hn', "limits", sys.argv[2]])
"""
        result = subprocess.run([sys.executable, "-c", code, str(initial_limit),
                                 str(REPO / "base-scripts/session-process-limits.sh")],
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return int(result.stdout.strip())

    def test_excessive_descriptor_limit_is_bounded_before_desktop_starts(self):
        import resource
        hard = resource.getrlimit(resource.RLIMIT_NOFILE)[1]
        if hard != resource.RLIM_INFINITY and hard < 1048576:
            self.skipTest("Host hard descriptor limit is below the regression input")
        self.assertEqual(self.session_limit(1048576), 65536)

    def test_lower_descriptor_limit_is_preserved(self):
        self.assertEqual(self.session_limit(4096), 4096)


@unittest.skipUnless(os.name == "posix", "Xsessions run inside Linux containers")
class DesktopSessionTests(unittest.TestCase):
    def test_user_startup_runs_and_preserves_its_exit_status(self):
        for status in (0, 7):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as folder:
                home = Path(folder)
                startup = home / ".config/tigervnc/xstartup"
                startup.parent.mkdir(parents=True)
                startup.write_text(f"#!/bin/sh\nprintf 'session-started\\n'\nexit {status}\n")
                startup.chmod(0o755)
                result = subprocess.run(
                    ["/bin/sh", str(REPO / "base-scripts/start-desktop-session.sh")],
                    env=dict(os.environ, HOME=str(home)),
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stdout, "session-started\n")


if __name__ == "__main__":
    unittest.main()
