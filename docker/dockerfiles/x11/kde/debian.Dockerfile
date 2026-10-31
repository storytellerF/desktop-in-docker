# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root
# Install KDE-specific packages
# kde-plasma-desktop is a minimal KDE installation
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    dbus-x11 \
    x11-xserver-utils \
    xfonts-base \
    kde-plasma-desktop \
    kwin-x11 \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=debian
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
# Using dbus-run-session is recommended for KDE to ensure a proper session bus
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export KWIN_COMPOSE=N" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startplasma-x11" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
