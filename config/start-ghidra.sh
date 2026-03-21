#!/bin/bash
if [ -z "$DISPLAY" ]; then
    echo "Error: \$DISPLAY not set. Run with: docker run -e DISPLAY=\$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix ..."
    exit 1
fi
exec ghidra "$@"
