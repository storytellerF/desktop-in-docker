ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:fedora-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

# __INJECT_BEFORE_DEPS__
RUN dnf install -y \
        supervisor \
        fcitx \
        fcitx-pinyin && \
    dnf clean all
