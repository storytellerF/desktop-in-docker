#!/bin/sh
set -eu
# Fedora's power manager restores a ten-minute X11 blanking timer at startup.
for source in ac battery; do
    xfconf-query --channel xfce4-power-manager \
        --property "/xfce4-power-manager/blank-on-$source" \
        --create --type int --set 0
done
exec startxfce4
