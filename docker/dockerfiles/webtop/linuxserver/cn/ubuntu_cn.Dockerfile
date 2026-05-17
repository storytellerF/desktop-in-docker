ARG WEBTOP_IMAGE=lscr.io/linuxserver/webtop:ubuntu-xfce
FROM ${WEBTOP_IMAGE}

USER root

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl bash && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
    --source mirrors.aliyun.com \
    --protocol https \
    --use-intranet-source false \
    --backup false \
    --upgrade-software false \
    --clean-cache false \
    --lang en \
    --pure-mode
