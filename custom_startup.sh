#!/usr/bin/env bash
set -ex

# PersonalDesktop Kasm Workspace Startup Script
# Full desktop environment with Signal, Delta Chat, and Vivaldi available

# Wait for the desktop environment to be ready
if [ -f /usr/bin/desktop_ready ]; then
    /usr/bin/desktop_ready
fi

# Desktop is ready - apps are available via desktop shortcuts and menu
# Users can launch Signal, Delta Chat, or Vivaldi from the desktop icons
