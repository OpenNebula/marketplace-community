#!/bin/bash

# timestap to use along scripts
export timestamp=$(date +"%Y%m%d_%H%M%S")

# Directories variables setup (no modification needed)
export BASE_DIR=$(dirname "$(readlink -f "$0")")

# Print scripts directory
echo "The /helm/scripts directory is: $SCRIPTS_DIR"

# Configuration needed before use installation/uninstallation scripts
export TEST_MESSAGE="This is a test message"
export TEST_MESSAGE2="This is a test message 2"