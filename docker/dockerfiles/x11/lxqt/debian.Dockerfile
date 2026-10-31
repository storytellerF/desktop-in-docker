# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root
# Install LXQt-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    dbus-x11 \
    x11-xserver-utils \
    xfonts-base \
    lxqt \
    openbox \
    papirus-icon-theme \
    qt6-svg-plugins \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=debian
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
# Using dbus-run-session is the modern way to ensure a fresh session bus
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxqt" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

# Select a window manager without a first-login chooser in the remote session.
RUN mkdir -p .config/lxqt
COPY --chown=${USERNAME} docker/config/lxqt/session.conf .config/lxqt/session.conf
