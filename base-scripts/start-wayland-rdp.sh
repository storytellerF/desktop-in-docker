#!/bin/bash
set -e

rdp_port=${RDP_PORT:-3389}
weston_config="${HOME}/.config/weston/weston.ini"
cert_dir="${HOME}/.config/weston"
cert_file="${cert_dir}/rdp.crt"
key_file="${cert_dir}/rdp.key"

mkdir -p "$cert_dir" "$HOME/log/supervisor"
mkdir -p "${XDG_RUNTIME_DIR:-$HOME/run}"
chmod 700 "${XDG_RUNTIME_DIR:-$HOME/run}"

if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
  echo "Generating Weston RDP TLS certificate."
  openssl req \
    -x509 \
    -nodes \
    -newkey rsa:2048 \
    -keyout "$key_file" \
    -out "$cert_file" \
    -days 3650 \
    -subj "/CN=desktop-in-docker-wayland-rdp"
  chmod 600 "$key_file"
  chmod 644 "$cert_file"
fi

echo "Starting Weston RDP on 0.0.0.0:${rdp_port}..."
exec dbus-run-session weston \
  --backend=rdp \
  --address=0.0.0.0 \
  --port="${rdp_port}" \
  --rdp-tls-cert="${cert_file}" \
  --rdp-tls-key="${key_file}" \
  --xwayland \
  --config="${weston_config}"
