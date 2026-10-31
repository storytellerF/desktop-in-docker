#!/bin/sh
set -eu
python3 /usr/local/lib/desktop-in-docker/enlightenment-no-lock.py "$HOME/.e/e/config"
exec enlightenment_start
