#!/bin/bash
set -e

# TigerVNC specific configuration
# TigerVNC needs a password to be set or explicitly allow no password
geometry=${VNC_GEOMETRY:-1280x800}
depth=${VNC_DEPTH:-24}

# TigerVNC 1.14+ configuration
mkdir -p ~/.config
TIGERVNC_CONF_DIR="$HOME/.config/tigervnc"
mkdir -p "$TIGERVNC_CONF_DIR"
TIGERVNC_CONFIG_FILE="$TIGERVNC_CONF_DIR/config"

if [ -n "$VNC_PASSWD" ]; then
  echo "Setting VNC password."
  # TigerVNC vncpasswd -f reads from stdin and writes to stdout
  echo "$VNC_PASSWD" | vncpasswd -f > "$TIGERVNC_CONF_DIR/passwd"
  chmod 600 "$TIGERVNC_CONF_DIR/passwd"
  VNC_SECURITY_TYPES="VncAuth"
else
  echo "VNC_PASSWD not set. VNC will start without a password."
  VNC_SECURITY_TYPES="None"
fi

cat > "$TIGERVNC_CONFIG_FILE" <<EOF
geometry=${geometry}
depth=${depth}
localhost=no
securitytypes=${VNC_SECURITY_TYPES}
EOF

if [ -n "$VNC_PASSWD" ]; then
  echo "rfbauth=$TIGERVNC_CONF_DIR/passwd" >> "$TIGERVNC_CONFIG_FILE"
fi

# Initialize .Xauthority file to avoid xauth warnings
if [ ! -f ~/.Xauthority ]; then
  echo "Initializing .Xauthority file."
  touch ~/.Xauthority
  chmod 600 ~/.Xauthority
fi

# Function to handle graceful shutdown
cleanup() {
  echo "Caught signal, stopping VNC server..."
  vncserver -kill :1 || true
  # Clean up any remaining lock files
  rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
  exit 0
}

# Trap SIGTERM and SIGINT signals
trap 'cleanup' SIGTERM SIGINT

# Remove potentially stale lock files before starting
echo "Removing potentially stale lock files before starting..."
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start VNC server
echo "Starting VNC server with geometry ${geometry} and depth ${depth}..."
# Use the TigerVNC config file for portability. Alpine/Arch variants only
# accept the display number as a CLI argument and read the rest from config.
vncserver :1

echo "VNC server is running."
# wait allows the script to catch signals
sleep infinity
