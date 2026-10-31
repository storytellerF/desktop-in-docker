#!/bin/sh
set -eu

# Alpine ships LXSession/PCManFM/Openbox, but not LXPanel or lxde-common.
# Build the missing upstream components against this image's own GTK libraries.
apk add --no-cache --virtual .lxde-build-deps \
    build-base autoconf automake libtool intltool gettext-dev curl \
    glib-dev gtk+3.0-dev libfm-dev libfm-extra-dev libexif-dev libwnck3-dev \
    keybinder3-dev menu-cache-dev libx11-dev alsa-lib-dev linux-headers

mkdir -p /tmp/lxde-build
cd /tmp/lxde-build
curl -fL --connect-timeout 15 --max-time 300 --retry 3 \
    https://github.com/lxde/lxpanel/archive/refs/tags/0.11.1.tar.gz -o lxpanel.tar.gz
echo '143e0afa28d30c596f9e1e915b3405d6266c36bd0b798ba0803b9bcd1d8be14a8363ff39505059b28d67da80f91ee04ee6682af3e1ce09e8cb194d36fafebd5b  lxpanel.tar.gz' | sha512sum -c -
tar -xf lxpanel.tar.gz
cd lxpanel-0.11.1
autoreconf -fi
./configure --prefix=/usr --sysconfdir=/etc --enable-gtk3 \
    --with-plugins=cpu,deskno,kbled,xkb,thermal,cpufreq,monitors,volume
make -j2
make install

cd /tmp/lxde-build
curl -fL --connect-timeout 15 --max-time 300 --retry 3 \
    'https://downloads.sourceforge.net/project/lxde/lxde-common%20%28default%20config%29/lxde-common%200.99/lxde-common-0.99.2.tar.xz' \
    -o lxde-common.tar.xz
echo '9eb939ad411ed15c6bae880541b5c021ce5f3dd66df8662865e2f7219159110d8bf6059a707e55863d04617b17a15ea517317c44f88982344369aa85b7128b6e  lxde-common.tar.xz' | sha512sum -c -
tar -xf lxde-common.tar.xz
cd lxde-common-0.99.2
./configure --prefix=/usr --sysconfdir=/etc
make -j2
make install

cd /
rm -rf /tmp/lxde-build
apk del .lxde-build-deps
command -v startlxde
command -v lxpanel
