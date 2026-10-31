#!/bin/sh
set -eu

# Alpine supplies EFL and Terminology in edge/testing, but not the modern
# Enlightenment desktop. Build the upstream desktop against the same edge EFL.
apk add --no-cache efl-dev@testing
apk add --no-cache --virtual .enlightenment-build-deps \
    build-base meson gettext-dev libexif-dev polkit-dev \
    linux-headers bsd-compat-headers curl

mkdir -p /tmp/enlightenment-build
cd /tmp/enlightenment-build
# Debian's original source archive is byte-identical to the upstream release.
# Its signed .dsc records this SHA256; do not replace this with an unpinned git tip.
curl -fsSL --connect-timeout 15 --max-time 1800 --retry 3 \
    https://deb.debian.org/debian/pool/main/e/e17/e17_0.27.1.orig.tar.xz -o enlightenment.tar.xz
echo 'b41df8771f60e3b96a1973ae566d7425c53a8339f18e54e31230218781da2fa9  enlightenment.tar.xz' | sha256sum -c -
tar -xf enlightenment.tar.xz
meson setup enlightenment-0.27.1/build enlightenment-0.27.1 \
    --prefix=/usr --libdir=lib --sysconfdir=/etc --buildtype=release \
    -Dsystemd=false -Dmount-udisks=false \
    -Dbluez5=false -Dconnman=false -Dpackagekit=false -Dpolkit=true \
    -Dpam=false -Dwl=false -Dnls=false
meson compile -C enlightenment-0.27.1/build -j2
meson install -C enlightenment-0.27.1/build
cd /
rm -rf /tmp/enlightenment-build
# Tagged world dependencies need repository indexes during removal too.
apk del --no-cache .enlightenment-build-deps efl-dev
command -v enlightenment_start
