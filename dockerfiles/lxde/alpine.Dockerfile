# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install LXDE on Alpine Linux
RUN apk add --no-cache \
    lxde \
    lxde-common \
    lxde-icon-theme \
    lxterminal \
    pcmanfm \
    openbox \
    xdg-utils \
    dbus-x11

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxde" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
