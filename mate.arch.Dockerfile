# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install MATE on Arch Linux
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    mate \
    mate-extra \
    xdg-utils \
    && pacman -Scc --noconfirm

ARG USERNAME=arch
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session mate-session" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
