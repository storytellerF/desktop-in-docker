#!/usr/bin/env python3
"""Offline Docker stand-in: record exact argv and selected Compose configuration."""

import json
import os
from pathlib import Path
import sys


def main():
    args = sys.argv[1:]
    keys = ("DOCKER_USERNAME", "IMAGE_TAG", "CONTAINER_HOME", "CONTAINER_WEB_PORT",
            "CONTAINER_VNC_PORT", "CONTAINER_RDP_PORT")
    with Path(os.environ["FAKE_DOCKER_LOG"]).open("a", encoding="utf-8") as log:
        log.write(json.dumps({"argv": args, "env": {key: os.environ.get(key) for key in keys}}) + "\n")
    if args[:1] == ["compose"]:
        rest = args[1:]
        if rest[:1] == ["-f"]:
            rest = rest[2:]
        key = "compose-" + (rest[0] if rest else "")
    else:
        key = "-".join(args[:2]) if args[:1] in (["buildx"], ["image"]) else args[0]
    failures = os.environ.get("FAKE_DOCKER_FAIL_COMMANDS", "").split(",")
    if key in failures or args[0] in failures:
        print(f"fake docker: forced failure for {key}", file=sys.stderr)
        return int(os.environ.get("FAKE_DOCKER_FAIL_EXIT_CODE", "1"))
    if key == "compose-port":
        port = args[-1]
        setting = "FAKE_DOCKER_WEB_PORT" if port in ("6080", "3000") else "FAKE_DOCKER_VNC_PORT" if port in ("5901", "3001") else "FAKE_DOCKER_PORT"
        default = "16080" if setting == "FAKE_DOCKER_WEB_PORT" else "15901" if setting == "FAKE_DOCKER_VNC_PORT" else "10000"
        print(f"[::]:{os.environ.get(setting, default)}")
    elif key not in ("build", "buildx-build", "image-prune", "compose-up", "compose-down"):
        print(f"fake docker: unsupported command {args!r}", file=sys.stderr)
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main())
