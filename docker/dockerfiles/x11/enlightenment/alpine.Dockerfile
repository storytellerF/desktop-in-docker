# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Use a complete edge base rather than mixing testing libraries into stable.
RUN grep -q '/edge/main' /etc/apk/repositories && \
    testing_repo="$(sed -n 's|/edge/community.*|/edge/testing|p' /etc/apk/repositories)" && \
    test -n "$testing_repo" && printf '@testing %s\n' "$testing_repo" >> /etc/apk/repositories && \
    apk add --no-cache \
    efl@testing \
    terminology@testing \
    acpid \
    adwaita-icon-theme \
    mesa-dri-gallium \
    dbus-x11 \
    dbus \
    xrdb \
    xdg-utils

COPY docker/build/build-alpine-enlightenment.sh /usr/local/libexec/build-alpine-enlightenment.sh
RUN sh /usr/local/libexec/build-alpine-enlightenment.sh

# Source-built binaries are not tracked by APK's shared-library dependency solver.
RUN apk add --no-cache libexif libpulse polkit && ldd /usr/bin/enlightenment

ARG USERNAME=alpine
# This account already has passwordless sudo; permit its desktop helper too.
RUN if [ -f /etc/enlightenment/system.conf ]; then \
    { printf 'user: %s allow: *\n' "$USERNAME"; cat /etc/enlightenment/system.conf; } > /tmp/enlightenment-system.conf && \
    mv /tmp/enlightenment-system.conf /etc/enlightenment/system.conf; fi

USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "[ -S /var/run/acpid.socket ] || sudo acpid" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session enlightenment_start" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
