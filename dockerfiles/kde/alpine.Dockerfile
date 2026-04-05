# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install KDE Plasma on Alpine Linux
RUN apk add --no-cache \
    plasma-desktop \
    plasma-workspace \
    kwin \
    konsole \
    dolphin \
    xdg-utils

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export KWIN_COMPOSE=N" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startplasma-x11" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
