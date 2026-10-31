# Source this before spawning desktop processes on musl. Older D-Bus and Qt
# child-process fallbacks can scan every descriptor up to the hard RLIMIT_NOFILE.
# Docker hosts may default to more than one billion descriptors, leaving the
# parent blocked in vfork while its child loops over fcntl calls.
_desktop_nofile_limit=$(ulimit -Hn)
if [ "$_desktop_nofile_limit" = unlimited ] || [ "$_desktop_nofile_limit" -gt 65536 ]; then
    ulimit -n 65536
fi
unset _desktop_nofile_limit
