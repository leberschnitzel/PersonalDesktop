#!/usr/bin/env bash
set -ex

# Kasm workspace startup - waits for desktop to be ready
if [ -f /usr/bin/desktop_ready ]; then
    /usr/bin/desktop_ready
fi
