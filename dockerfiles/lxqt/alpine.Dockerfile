# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install LXQt on Alpine Linux
RUN apk add --no-cache \
    lxqt \
    xdg-utils \
    xdg-user-dirs

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxqt" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
