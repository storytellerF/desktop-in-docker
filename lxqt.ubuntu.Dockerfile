# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root
# Install LXQt-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    lxqt-core \
    lxqt-panel \
    lxqt-session \
    lxqt-qtplugin \
    lxqt-config \
    qterminal \
    pcmanfm-qt \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=ubuntu
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "startlxqt" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
