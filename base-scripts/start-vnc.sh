#!/bin/bash
set -e

# Set VNC password if VNC_PASSWD environment variable is set
if [ -n "$VNC_PASSWD" ]; then
  echo "Setting VNC password."
  mkdir -p ~/.vnc
  echo "$VNC_PASSWD" | vncpasswd -f > ~/.vnc/passwd
  chmod 600 ~/.vnc/passwd
else
  echo "VNC_PASSWD not set. VNC will start without a password."
fi

# Initialize .Xauthority file to avoid xauth warnings (only if it doesn't exist)
if [ ! -f ~/.Xauthority ]; then
  echo "Initializing .Xauthority file."
  touch ~/.Xauthority
  chmod 600 ~/.Xauthority
fi

# Function to handle graceful shutdown
cleanup() {
  echo "Caught signal, stopping VNC server..."
  vncserver -kill :1 || true
  rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1
  exit 0
}

# Trap SIGTERM and SIGINT signals
trap 'cleanup' SIGTERM SIGINT

# Remove potentially stale lock files before starting
echo "Removing potentially stale lock files before starting..."
rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1

# Start VNC server
echo "Starting VNC server..."
geometry=${VNC_GEOMETRY:-1280x800}
depth=${VNC_DEPTH:-24}
vncserver :1 -geometry $geometry -depth $depth

# Tail logs in background and wait
# waiting allows the script to catch signals
echo "Waiting for VNC server to start..."
sleep infinity