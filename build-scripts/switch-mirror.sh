#!/bin/sh
set -eu

if [ "${USE_CN_MIRROR:-false}" != "true" ]; then
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "switch-mirror.sh must run as root" >&2
    exit 1
fi

install_prerequisites() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends --no-install-suggests \
        curl \
        ca-certificates \
        bash
        rm -rf /var/lib/apt/lists/*
        return
    fi

    if command -v dnf >/dev/null 2>&1; then
        dnf install -y curl ca-certificates bash
        dnf clean all
        return
    fi

    if command -v pacman >/dev/null 2>&1; then
        pacman-key --init
        pacman-key --populate archlinux
        pacman -Sy --noconfirm --needed curl ca-certificates bash
        pacman -Scc --noconfirm
        return
    fi

    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl ca-certificates bash
        update-ca-certificates || true
        return
    fi

    echo "Unsupported package manager for mirror switching" >&2
    exit 1
}

install_prerequisites

curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
    --source mirrors.aliyun.com \
    --protocol https \
    --use-intranet-source false \
    --backup false \
    --upgrade-software false \
    --clean-cache false \
    --lang en \
    --pure-mode