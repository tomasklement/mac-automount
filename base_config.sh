#!/bin/bash

# Interval in which is checked the mount state of drives [seconds]
REFRESH_INTERVAL="10"

# Mac library directory path
readonly LIBRARY_DIR="/Library/LaunchDaemons"

# Directory with particular mounts configurations
readonly MOUNTS_CONFIG_DIR="mounts_config"

# File with custom config
readonly CUSTOM_CONFIG_FILE_NAME="config.sh"

# App name for launchctl
readonly APP_NAME="application.com.tomasklement.automount"