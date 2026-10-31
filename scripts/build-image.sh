#!/usr/bin/env bash
# Compatibility entry point; all build logic lives in Python.
exec "${PYTHON:-python3}" "$(dirname "$0")/build_image.py" "$@"
