# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install Enlightenment on Arch Linux (available in community repo)
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    enlightenment \
    xdg-utils \
    && pacman -Scc --noconfirm

ARG USERNAME=arch
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session enlightenment_start" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
