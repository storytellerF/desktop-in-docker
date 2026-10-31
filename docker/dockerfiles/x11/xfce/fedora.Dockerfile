# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install XFCE on Fedora
RUN dnf install -y \
    @xfce-desktop-environment \
    dbus-x11 \
    xdg-utils \
    && dnf clean all

ARG USERNAME=user
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "startxfce4" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

# This login-session authentication agent cannot register in a VNC container.
RUN mkdir -p .config/autostart
COPY --chown=${USERNAME} docker/config/autostart/disabled.desktop .config/autostart/xfce-polkit.desktop
