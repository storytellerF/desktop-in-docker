#!/usr/bin/env python3
"""Build, publish and run desktop images using only the Python standard library."""

import argparse
from dataclasses import dataclass, replace
from datetime import datetime
import json
import os
from pathlib import Path
import secrets
import string
import subprocess
import sys
from uuid import uuid4


DEFAULT_VERSIONS = {"debian": "trixie", "ubuntu": "noble", "fedora": "41",
                    "arch": "latest", "alpine": "latest"}
DESKTOPS = ("xfce", "lxqt", "kde", "mate", "cinnamon", "lxde", "gnome", "enlightenment")
# Keep each Alpine desktop on a complete, ABI-consistent repository branch.
# Newer GNOME/Plasma packages no longer provide the X11 sessions used by VNC.
ALPINE_X11_VERSIONS = {"cinnamon": "edge", "enlightenment": "edge",
                       "gnome": "3.22", "kde": "3.21"}
# Only upstream desktop tags verified to exist are accepted in Webtop mode.
WEBTOP_DESKTOPS = {
    "debian": ("xfce", "kde", "mate"),
    "ubuntu": ("xfce", "lxqt", "kde", "mate"),
    "fedora": ("xfce", "kde", "mate"),
    "arch": ("xfce", "kde", "mate"),
    "alpine": ("kde",),
}
UBUNTU_VERSIONS = {"trusty", "xenial", "bionic", "focal", "jammy", "kinetic", "lunar",
                   "mantic", "noble", "14.04", "16.04", "18.04", "20.04", "22.04",
                   "22.10", "23.04", "23.10", "24.04"}
CN_TIMEZONES = {"Asia/Shanghai", "Asia/Chongqing", "Asia/Harbin", "Asia/Urumqi", "PRC"}
MARKER = "__INJECT_BEFORE_DEPS__"


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    for short, name, help_text in (
        ("s", "system", "Linux distribution (default: debian; Wayland: arch only)"),
        ("v", "version", "Distribution version"),
        ("p", "password", "VNC password (default: password)"),
        ("d", "desktop", "Desktop (default: xfce; Wayland: weston only)"),
    ):
        result.add_argument(f"-{short}", f"--{name}", help=help_text)
    result.add_argument("-i", "--image-variant", "--variant", help="x11, wayland or webtop")
    for short, name, help_text in (
        ("c", "create-env", "Interactively update .env"),
        ("b", "build", "Build images locally"),
        ("S", "start", "Start Docker Compose"),
        ("T", "stop", "Stop Docker Compose before starting"),
        ("P", "publish", "Build and push amd64/arm64 images (requires docker login)"),
        ("m", "multi-arch", "Compatibility flag; publishing always builds amd64/arm64"),
    ):
        result.add_argument(f"-{short}", f"--{name}", action="store_true", help=help_text)
    mirrors = result.add_mutually_exclusive_group()
    mirrors.add_argument("--cn-mirror", dest="mirror", action="store_const", const="on")
    mirrors.add_argument("--no-cn-mirror", dest="mirror", action="store_const", const="off")
    result.add_argument("--latest", action="store_true", help="Add latest tags")
    result.add_argument("--no-snapshot", action="store_true", help="Omit snapshot tags")
    return result


def parse_env_value(value, number):
    """Decode a quoted literal before considering its trailing comment."""
    if not value.startswith(('"', "'")):
        return value.split(" #", 1)[0].rstrip()
    quote = value[0]
    decoded = []
    escapes = {'"': '"', "\\": "\\", "/": "/", "n": "\n", "r": "\r",
               "t": "\t", "b": "\b", "f": "\f"}
    index = 1
    while index < len(value):
        char = value[index]
        if char == quote:
            trailing = value[index + 1:].strip()
            if trailing and not trailing.startswith("#"):
                raise ValueError(f"Invalid .env value at line {number}")
            return "".join(decoded)
        if char == "\\" and index + 1 < len(value):
            escaped = value[index + 1]
            if quote == '"' and escaped in escapes:
                decoded.append(escapes[escaped])
                index += 2
                continue
            # Preserve JSON control-character escapes emitted by update_env.
            if quote == '"' and escaped == "u" and index + 6 <= len(value):
                digits = value[index + 2:index + 6]
                if all(digit in string.hexdigits for digit in digits):
                    width = 6
                    following = value[index + 6:index + 12]
                    if (following.startswith("\\u") and len(following) == 6
                            and all(digit in string.hexdigits for digit in following[2:])):
                        width = 12
                    decoded.append(json.loads('"' + value[index:index + width] + '"'))
                    index += width
                    continue
            # Other backslashes are literal, such as the one in abc\q.
        decoded.append(char)
        index += 1
    raise ValueError(f"Unclosed .env quote at line {number}")


def load_env(path):
    """Read literal KEY=value assignments; never execute shell code or expand variables."""
    values = {}
    if path.exists():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, sep, value = line.removeprefix("export ").partition("=")
            key, value = key.strip(), value.strip()
            if not sep or not key.isidentifier():
                raise ValueError(f"Invalid .env assignment at line {number}")
            values[key] = parse_env_value(value, number)
    return values


def update_env(path, values):
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    remaining = dict(values)
    output = []
    for line in lines:
        key = line.strip().removeprefix("export ").partition("=")[0].strip()
        if key in values:
            if key in remaining:
                output.append(f"{key}={json.dumps(remaining.pop(key), ensure_ascii=False)}")
        else:
            output.append(line)
    output.extend(f"{key}={json.dumps(value, ensure_ascii=False)}" for key, value in remaining.items())
    path.write_text("\n".join(output) + "\n", encoding="utf-8")


def timezone(env):
    if env.get("TZ"):
        return env["TZ"]
    path = Path("/etc/timezone")
    if path.is_file():
        return path.read_text().strip()
    localtime = Path("/etc/localtime").resolve().as_posix()
    return localtime.split("/zoneinfo/", 1)[1] if "/zoneinfo/" in localtime else "UTC"


@dataclass(frozen=True)
class Config:
    system: str
    version: str
    desktop: str
    variant: str
    cn: bool
    tz: str
    timestamp: str
    username: str
    password: str
    rdp_port: str

    @classmethod
    def from_args(cls, args, env):
        system = args.system or env.get("SYSTEM") or "debian"
        variant = args.image_variant or env.get("IMAGE_VARIANT") or "x11"
        desktop = args.desktop or ("weston" if variant == "wayland" else env.get("DESKTOP_ENV") or "xfce")
        default_version = (ALPINE_X11_VERSIONS.get(desktop, "latest")
                           if system == "alpine" and variant == "x11"
                           else DEFAULT_VERSIONS.get(system, "latest"))
        version = args.version or env.get("SYSTEM_VERSION") or default_version
        if system not in DEFAULT_VERSIONS:
            raise ValueError(f"Unsupported system: {system}")
        if variant not in ("x11", "wayland", "webtop"):
            raise ValueError(f"Unknown image variant: {variant}")
        if variant == "x11" and system == "arch":
            raise ValueError("x11 does not support --system arch")
        if variant == "wayland" and system != "arch":
            raise ValueError("wayland supports --system arch only")
        if variant == "wayland" and desktop != "weston":
            raise ValueError("wayland supports --desktop weston only")
        if variant != "wayland" and desktop not in DESKTOPS:
            raise ValueError(f"Unsupported desktop: {desktop}")
        if variant in ("x11", "webtop") and system == "alpine" and desktop == "mate":
            raise ValueError(f"{variant} does not support alpine/mate: this combination is disabled")
        if variant == "x11" and system == "ubuntu" and version not in UBUNTU_VERSIONS:
            raise ValueError("x11 with ubuntu supports noble/24.04 or earlier only")
        if variant == "webtop" and desktop not in WEBTOP_DESKTOPS[system]:
            supported = ", ".join(WEBTOP_DESKTOPS[system])
            raise ValueError(f"webtop does not support {system}/{desktop}; supported desktops: {supported}")
        tz = timezone(env)
        legacy = {"true": "on", "false": "off"}.get(env.get("ENABLE_CN_MIRROR"))
        mirror = args.mirror or env.get("CN_MIRROR_MODE") or legacy or "auto"
        if mirror not in ("on", "off", "auto"):
            raise ValueError("CN_MIRROR_MODE must be on, off or auto")
        return cls(system, version, desktop, variant,
                   mirror == "on" or (mirror == "auto" and tz in CN_TIMEZONES), tz,
                   datetime.now().strftime("%Y%m%d%H%M%S"), env.get("DOCKER_USERNAME", ""),
                   args.password or env.get("VNC_PASSWD") or "password", env.get("RDP_PORT") or "3389")

    @property
    def user(self):
        return "abc" if self.variant == "webtop" else {"fedora": "user"}.get(self.system, self.system)

    @property
    def image(self):
        return (self.username + "/" if self.username else "") + "desktop-in-docker"

    def prefixes(self):
        full = f"{self.system}-{self.version}"
        short = "" if (self.system, self.version) == ("debian", "trixie") else full
        base, short_base = full + "-base", f"{short}-base" if short else "base"
        desktop = f"{full}-{self.desktop}"
        short_desktop = "-".join(filter(None, (short, "" if self.desktop == "xfce" else self.desktop)))
        if self.variant == "wayland":
            base, desktop = "wayland-" + base, "wayland-" + desktop
            short_base, short_desktop = base, desktop
        elif self.variant == "webtop":
            full = f"webtop-{self.system}-{self.desktop}"
            short = "-".join(filter(None, ("webtop", "" if self.system == "debian" else self.system,
                                            "" if self.desktop == "xfce" else self.desktop)))
            base, short_base, desktop, short_desktop = full + "-base", short + "-base", full, short
        if self.cn:
            base, short_base, desktop, short_desktop = (
                f"{prefix}-cn" if prefix else "cn" for prefix in (base, short_base, desktop, short_desktop))
        return base, short_base, desktop, short_desktop


class Docker:
    """Run Docker synchronously, preserving argument boundaries and failure status."""

    def __init__(self, root, env, command=("docker",)):
        self.root, self.env, self.command = root, env, command

    def run(self, *args, capture=False):
        return subprocess.run([*self.command, *args], cwd=self.root, env=self.env,
                              check=True, text=True, encoding="utf-8", capture_output=capture)


def choose(root, preferred, fallback):
    return preferred if (root / preferred).is_file() else fallback


def merge(root, source, output, injections, appended):
    text = (root / source).read_text(encoding="utf-8")
    fragments = [(path, (root / path).read_text(encoding="utf-8")) for path in (*injections, *appended)]
    if injections and MARKER not in text:
        raise ValueError(f"Injection marker {MARKER} not found in {source}")
    lines = [f"# Source: {source}\n"]
    for line in text.splitlines(keepends=True):
        lines.append(line)
        if MARKER in line:
            for path, content in fragments[:len(injections)]:
                lines.append(f"\n# Source: {path}\n{content}\n")
    for path, content in fragments[len(injections):]:
        lines.append(f"\n# Source: {path}\n{content}\n")
    destination = root / output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("".join(lines), encoding="utf-8")
    print(f"Merged Dockerfile: {output}")


def prepare(root, config):
    c = config
    suffix = "_cn" if c.cn else ""
    # Docker reads this file after preparation; another build must never replace it.
    merged = f"build/{c.variant}/{uuid4().hex}/{c.system}{suffix}.Dockerfile"
    fragments = "docker/dockerfiles/fragments"
    injections, appended = [], []
    if c.variant == "webtop":
        source = choose(root, f"docker/dockerfiles/webtop/{c.system}.Dockerfile",
                        "docker/dockerfiles/webtop/debian.Dockerfile")
        if c.cn:
            injections.append(choose(root, f"{fragments}/webtop/cn/{c.system}_cn.dockerfrag",
                                     f"{fragments}/webtop/cn/debian_cn.dockerfrag"))
        appended.append(f"{fragments}/webtop/config.dockerfrag")
        if c.system == "alpine" and c.desktop == "kde":
            appended.append(f"{fragments}/webtop/alpine-kde.dockerfrag")
        desktop = merged
    else:
        if c.variant == "wayland":
            source = "docker/dockerfiles/wayland/base/arch.Dockerfile"
            desktop = "docker/dockerfiles/wayland/weston/arch.Dockerfile"
        else:
            source = choose(root, f"docker/dockerfiles/base/{c.system}.Dockerfile",
                            "docker/dockerfiles/base/debian.Dockerfile")
            desktop = choose(root, f"docker/dockerfiles/x11/{c.desktop}/{c.system}.Dockerfile",
                             f"docker/dockerfiles/x11/{c.desktop}/debian.Dockerfile")
            appended.append(f"{fragments}/custom/user-config.dockerfrag")
            if c.cn:
                appended.append(f"{fragments}/custom/fcitx-config.dockerfrag")
        if c.system == "alpine" and c.version == "edge":
            injections.append(f"{fragments}/base/alpine-edge-repositories.dockerfrag")
        if c.cn:
            injections.append(choose(root, f"{fragments}/base/cn/{c.system}_cn.dockerfrag",
                                     f"{fragments}/base/cn/debian_cn.dockerfrag"))
        if c.system == "debian":
            injections.append(f"{fragments}/base/cn/firefox-tuna.dockerfrag" if c.cn
                              else f"{fragments}/base/firefox-mozilla.dockerfrag")
        if not (root / desktop).is_file():
            raise ValueError(f"Desktop Dockerfile not found: {desktop}")
    merge(root, source, merged, injections, appended)
    if c.variant == "x11":
        prepared_desktop = Path(merged).with_name("desktop.Dockerfile").as_posix()
        desktop_fragments = [f"{fragments}/custom/remove-screensavers.dockerfrag"]
        if c.desktop == "cinnamon":
            desktop_fragments.append(f"{fragments}/custom/cinnamon-no-lock.dockerfrag")
        elif c.desktop == "enlightenment":
            desktop_fragments.append(f"{fragments}/custom/enlightenment-no-lock.dockerfrag")
        elif c.desktop == "kde":
            desktop_fragments.append(f"{fragments}/custom/kde-no-lock.dockerfrag")
        elif c.desktop == "xfce" and c.system == "fedora":
            desktop_fragments.append(f"{fragments}/custom/fedora-xfce-no-idle.dockerfrag")
        elif c.desktop == "mate":
            desktop_fragments.append(f"{fragments}/custom/mate-no-lock.dockerfrag")
        merge(root, desktop, prepared_desktop, [], desktop_fragments)
        desktop = prepared_desktop
    return merged, desktop


def tags(config, args, full, short):
    suffixes = [config.timestamp]
    if args.latest:
        suffixes.append("latest")
    if not args.no_snapshot:
        suffixes.append("snapshot")
    return [f"{config.image}:{prefix + '-' if prefix else ''}{suffix}"
            for prefix in dict.fromkeys((full, short)) for suffix in suffixes]


def build(root, c, args, docker):
    base_file, desktop_file = prepare(root, c)
    base, short_base, desktop, short_desktop = c.prefixes()
    base_tags, desktop_tags = tags(c, args, base, short_base), tags(c, args, desktop, short_desktop)
    base_args = ["--build-arg", f"BASE_FROM_IMAGE={'archlinux' if c.system == 'arch' else c.system}:{c.version}",
                 "--build-arg", f"SYSTEM={c.system}", "--build-arg", f"SYSTEM_VERSION={c.version}",
                 "--build-arg", f"USERNAME={c.user}", "--build-arg", f"TIMEZONE={c.tz}"]
    desktop_args = (["--build-arg", f"WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:{c.system}-{c.desktop}"]
                    if c.variant == "webtop" else
                    ["--build-arg", f"BASE_IMAGE={c.image}:{base}-{c.timestamp}",
                     "--build-arg", f"DESKTOP_ENV={c.desktop}", "--build-arg", f"USERNAME={c.user}"])
    command = ["buildx", "build", "--platform", "linux/amd64,linux/arm64"] if args.publish else ["build"]
    push = ["--push"] if args.publish else []
    stages = [] if c.variant == "webtop" else [(base_file, base_args, base_tags)]
    stages.append((desktop_file, desktop_args, desktop_tags))
    for dockerfile, build_args, image_tags in stages:
        tag_args = [value for tag in image_tags for value in ("-t", tag)]
        docker.run(*command, *build_args, *tag_args, *push, "-f", dockerfile, ".")
        print("Image tags:\n  " + "\n  ".join(image_tags))


def compose(c, args, docker):
    if args.stop:
        docker.run("compose", "-f", "docker-compose.yml", "down")
    if not args.start:
        return
    desktop = c.prefixes()[2]
    suffix = "latest" if args.latest else c.timestamp if args.no_snapshot else "snapshot"
    ports = (c.rdp_port,) if c.variant == "wayland" else ("3000", "3001") if c.variant == "webtop" else ("6080", "5901")
    docker.env.update(DOCKER_USERNAME=c.username or "storytellerf", IMAGE_TAG=f"{desktop}-{suffix}",
                      CONTAINER_HOME="/config" if c.variant == "webtop" else f"/home/{c.user}",
                      CONTAINER_WEB_PORT="" if c.variant == "wayland" else ports[0],
                      CONTAINER_VNC_PORT="" if c.variant == "wayland" else ports[1],
                      CONTAINER_RDP_PORT=c.rdp_port if c.variant == "wayland" else "", VNC_PASSWD=c.password)
    docker.run("compose", "-f", "docker-compose.yml", "up", "-d", "--build")
    for port in ports:
        try:
            result = docker.run("compose", "port", "desktop", port, capture=True)
        except subprocess.CalledProcessError:
            print(f"Port mapping not found (container port {port})", file=sys.stderr)
            continue
        mappings = result.stdout.strip().splitlines()
        if not mappings:
            print(f"Port mapping not found (container port {port})", file=sys.stderr)
            continue
        mapped = mappings[0].rsplit(":", 1)[-1]
        if c.variant == "wayland":
            print(f"RDP: localhost:{mapped}")
        elif port == ports[0]:
            print(f"Web: http://localhost:{mapped}/" + ("vnc.html" if c.variant == "x11" else ""))
        else:
            print(f"VNC direct: localhost:{mapped}")


def main(argv=None, *, root=None, environ=None, docker_command=("docker",)):
    args = parser().parse_args(argv)
    root = Path.cwd() if root is None else Path(root)
    env = dict(os.environ if environ is None else environ)
    try:
        if args.stop and not (args.start or args.build or args.publish or args.create_env):
            Docker(root, env, docker_command).run("compose", "-f", "docker-compose.yml", "down")
            return 0
        env.update(load_env(root / ".env"))
        c = Config.from_args(args, env)
        if args.create_env:
            password = input("Enter VNC password (empty: keep current, r: random): ")
            if password == "r":
                password = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
            username = input(f"Enter Docker Hub username (default: {c.username}, optional): ")
            update_env(root / ".env", {"DOCKER_USERNAME": username or c.username,
                                      "VNC_PASSWD": password or c.password, "IMAGE_TIMESTAMP": c.timestamp})
            env.update(load_env(root / ".env"))
            c = Config.from_args(args, env)
            # Interactive values take precedence over the initial password argument.
            c = replace(c, password=env["VNC_PASSWD"])
            print(".env file updated.")
        print(f"Timezone: {c.tz}; China mirror mode: {'enabled' if c.cn else 'disabled'}")
        docker = Docker(root, env, docker_command)
        if args.build or args.publish:
            build(root, c, args, docker)
        compose(c, args, docker)
        return 0
    except subprocess.CalledProcessError as error:
        print(f"Docker command failed (exit {error.returncode})", file=sys.stderr)
        return error.returncode if error.returncode > 0 else 1
    except (OSError, ValueError, EOFError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
