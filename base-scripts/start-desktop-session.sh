#!/bin/sh
# Alpine's TigerVNC selects an Xsession instead of reading xstartup directly.
. "$(dirname "$0")/session-process-limits.sh"
exec "$HOME/.config/tigervnc/xstartup"
