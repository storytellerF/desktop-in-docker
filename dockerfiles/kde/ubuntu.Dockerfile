# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root
# Prevent installation of power-management and screen-lock packages via APT pinning
RUN printf 'Package: %s\nPin: release *\nPin-Priority: -1\n\n' \
    upower \
    power-profiles-daemon \
    powerdevil \
    kscreenlocker-common \
    xscreensaver \
    xscreensaver-data \
    gnome-screensaver \
    mate-screensaver \
    cinnamon-screensaver \
    light-locker \
    xfce4-screensaver \
    > /etc/apt/preferences.d/no-desktop-extras

# Install KDE-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    kde-plasma-desktop \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=ubuntu
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export KWIN_COMPOSE=N" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startplasma-x11" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
