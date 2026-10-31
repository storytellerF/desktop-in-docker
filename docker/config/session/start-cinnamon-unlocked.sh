#!/bin/sh
set -eu
# Cinnamon requires its saver package; keep the dependency but disable activation.
gsettings set org.cinnamon.desktop.lockdown disable-lock-screen true
gsettings set org.cinnamon.desktop.screensaver lock-enabled false
gsettings set org.cinnamon.desktop.screensaver idle-activation-enabled false
gsettings set org.cinnamon.desktop.keybindings.media-keys screensaver '[]'
gsettings set org.cinnamon.settings-daemon.plugins.media-keys screensaver "''"
# Cinnamon assigns Super+L to its debugger rather than to the locker.
gsettings set org.cinnamon.desktop.keybindings looking-glass-keybinding '[]'
exec cinnamon-session
