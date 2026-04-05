# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install LXDE on Fedora
RUN dnf install -y \
    @lxde-desktop-environment \
    xdg-utils \
    && dnf clean all

ARG USERNAME=user
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxde" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
