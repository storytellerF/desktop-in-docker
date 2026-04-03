# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install XFCE on Alpine Linux via apk
# edge/community repo contains xfce4
RUN apk add --no-cache \
    xfce4 \
    xfce4-terminal \
    xfce4-whiskermenu-plugin \
    dbus-x11 \
    adwaita-icon-theme \
    gvfs \
    thunar-volman

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "startxfce4" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
