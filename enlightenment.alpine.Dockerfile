# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root

# Install Enlightenment on Alpine Linux
RUN apk add --no-cache \
    enlightenment \
    terminology \
    xdg-utils

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session enlightenment_start" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
