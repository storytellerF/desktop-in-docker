# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install Enlightenment on Fedora
RUN dnf install -y \
    enlightenment \
    terminology \
    dbus-x11 \
    xdg-utils \
    && dnf clean all

RUN dnf install -y acpid && dnf clean all

ARG USERNAME=user
# This account already has passwordless sudo; permit its desktop helper too.
RUN if [ -f /etc/enlightenment/system.conf ]; then \
    { printf 'user: %s allow: *\n' "$USERNAME"; cat /etc/enlightenment/system.conf; } > /tmp/enlightenment-system.conf && \
    mv /tmp/enlightenment-system.conf /etc/enlightenment/system.conf; fi

USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "if [ -d /proc/acpi ] && [ ! -S /var/run/acpid.socket ]; then sudo acpid; fi" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session enlightenment_start" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup
