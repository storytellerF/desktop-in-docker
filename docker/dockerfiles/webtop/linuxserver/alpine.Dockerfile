ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:alpine-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

RUN apk add --no-cache \
        supervisor \
        fcitx5 \
        fcitx5-chinese-addons
