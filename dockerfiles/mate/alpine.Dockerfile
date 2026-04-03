# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install MATE on Alpine Linux
RUN apk add --no-cache \
    mate-desktop \
    mate-panel \
    mate-session-manager \
    mate-terminal \
    caja \
    marco \
    dbus-x11 \
    xdg-utils

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session mate-session" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
