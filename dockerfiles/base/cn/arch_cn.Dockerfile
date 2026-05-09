ARG SYSTEM_VERSION=latest
FROM archlinux:${SYSTEM_VERSION}

RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm --needed curl ca-certificates bash && \
    pacman -Scc --noconfirm && \
    bash -o pipefail -c 'curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
        --source mirrors.aliyun.com \
        --protocol https \
        --use-intranet-source false \
        --backup false \
        --upgrade-software false \
        --clean-cache false \
        --lang en \
        --pure-mode'
