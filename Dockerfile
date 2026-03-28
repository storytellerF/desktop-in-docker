# Base Image
FROM debian:trixie

ARG OPENJDK_VERSION

# Install Dependencies: VNC, Desktop, Supervisor, Java, KVM, and other tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends --no-install-suggests \
    dbus-x11 \
    supervisor \
    tightvncserver xfonts-base\
    xfce4 xfce4-terminal \
    novnc \
    wget \
    unzip \
    locales \
    sudo \
    pv \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Setup a non-root user
ARG USERNAME=debian
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME

# Copy Scripts
COPY --chown=${USER_UID}:${USER_GID} base-scripts ./bin
RUN chmod +x ./bin/*.sh

# Setup the startup script for the VNC server to launch the XFCE desktop
RUN mkdir -p .vnc && \
    echo "#!/bin/bash" > .vnc/xstartup && \
    echo "xrdb \$HOME/.Xresources" >> .vnc/xstartup && \
    echo "startxfce4 &" >> .vnc/xstartup && \
    chmod +x .vnc/xstartup

RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/${USERNAME}/.android-in-docker/.bash_history" \
    && echo "$SNIPPET" >> ~/.bashrc

RUN mkdir -p log/supervisor run

# Copy supervisor configuration
COPY --chown=${USER_UID}:${USER_GID} supervisord.conf ./supervisor/supervisord.conf

# 主要用于supervisor
ENV SUPERVISOR_USER=$USERNAME

# Expose Ports:
# 6080: noVNC Web Interface
# 5901: VNC Server (for display :1)
EXPOSE 6080 5901

# Command to run supervisor
# ENTRYPOINT ["sh", "-c", "tail -f /dev/null"]
ENTRYPOINT ["sh", "-c", "$HOME/bin/entrypoint.sh"]
