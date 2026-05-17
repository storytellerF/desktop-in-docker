ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:fedora-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

RUN dnf install -y \
        supervisor \
        fcitx \
        fcitx-pinyin && \
    dnf clean all
