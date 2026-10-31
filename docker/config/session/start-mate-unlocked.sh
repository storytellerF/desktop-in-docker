#!/bin/sh
set -eu
# Removing the saver leaves MATE's native lock action and key binding enabled.
gsettings set org.mate.lockdown disable-lock-screen true
gsettings set org.mate.SettingsDaemon.plugins.media-keys screensaver "''"
exec mate-session
