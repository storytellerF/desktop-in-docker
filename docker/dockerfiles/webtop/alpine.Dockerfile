ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:alpine-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

# __INJECT_BEFORE_DEPS__
RUN apk add --no-cache \
        supervisor
