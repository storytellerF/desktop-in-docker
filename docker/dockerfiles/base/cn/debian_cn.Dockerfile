ARG SYSTEM_VERSION=trixie
ARG BASE_FROM_IMAGE=debian:${SYSTEM_VERSION}
FROM ${BASE_FROM_IMAGE}

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends --no-install-suggests \
    curl \
    ca-certificates \
    bash && \
    rm -rf /var/lib/apt/lists/*

RUN bash -o pipefail -c 'curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
        --source mirrors.aliyun.com \
        --protocol https \
        --use-intranet-source false \
        --backup false \
        --upgrade-software false \
        --clean-cache false \
        --lang en \
        --pure-mode'

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    fcitx \
    fcitx-googlepinyin && \
    rm -rf /var/lib/apt/lists/*
