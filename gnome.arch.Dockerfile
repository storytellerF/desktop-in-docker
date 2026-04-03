# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install GNOME on Arch Linux
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    gnome \
    gnome-extra \
    xdg-utils \
    && pacman -Scc --noconfirm

ARG USERNAME=arch
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export DISPLAY=:1" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session gnome-session" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
