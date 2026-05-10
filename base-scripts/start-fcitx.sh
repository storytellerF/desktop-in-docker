#!/bin/bash
set -e

if [ -x /usr/bin/fcitx ]; then
  exec /usr/bin/fcitx -D
fi

if [ -x /usr/bin/fcitx5 ]; then
  exec /usr/bin/fcitx5 -r
fi

echo "fcitx not installed; skipping."
exit 0
