# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install KDE Plasma on Arch Linux
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    plasma-desktop \
    kde-applications-meta \
    xdg-utils \
    && pacman -Scc --noconfirm

ARG USERNAME=arch
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export KWIN_COMPOSE=N" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startplasma-x11" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
