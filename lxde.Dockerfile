# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root
# Prevent installation of power-management and screen-lock packages via APT pinning
RUN printf 'Package: %s\nPin: release *\nPin-Priority: -1\n\n' \
    upower \
    power-profiles-daemon \
    lxde-common \
    xscreensaver \
    xscreensaver-data \
    gnome-screensaver \
    mate-screensaver \
    cinnamon-screensaver \
    kscreenlocker-common \
    light-locker \
    xfce4-screensaver \
    > /etc/apt/preferences.d/no-desktop-extras

# Install LXDE-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    lxde \
    && rm -rf /var/lib/apt/lists/*

USER debian
WORKDIR /home/debian

# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxde" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
