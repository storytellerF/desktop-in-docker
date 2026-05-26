ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:arch-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

# __INJECT_BEFORE_DEPS__
RUN pacman-key --init || true && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm --needed \
        supervisor \
        fcitx5 \
        fcitx5-chinese-addons && \
    pacman -Scc --noconfirm
