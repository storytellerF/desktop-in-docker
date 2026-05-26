ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:debian-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

# __INJECT_BEFORE_DEPS__
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        supervisor \
        fcitx \
        fcitx-googlepinyin && \
    rm -rf /var/lib/apt/lists/*
