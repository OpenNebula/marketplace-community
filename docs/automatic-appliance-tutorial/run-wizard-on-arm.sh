#!/bin/bash

# Helper script to run the wizard on an ARM machine via SSH
# Usage: ./run-wizard-on-arm.sh user@arm-host

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 user@arm-host"
    echo "Example: $0 root@raspberrypi5"
    exit 1
fi

ARM_HOST="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Copying updated scripts to ARM machine: $ARM_HOST"

# Create directory on ARM machine if it doesn't exist
ssh "$ARM_HOST" "mkdir -p ~/marketplace-community/docs/automatic-appliance-tutorial"

# Copy the updated scripts
scp "$SCRIPT_DIR/appliance-wizard.sh" "$ARM_HOST:~/marketplace-community/docs/automatic-appliance-tutorial/"
scp "$SCRIPT_DIR/generate-docker-appliance.sh" "$ARM_HOST:~/marketplace-community/docs/automatic-appliance-tutorial/"

echo "✅ Scripts copied successfully"
echo ""
echo "🚀 Launching wizard on ARM machine..."
echo ""

# Run the wizard on the ARM machine
ssh -t "$ARM_HOST" "cd ~/marketplace-community/docs/automatic-appliance-tutorial && ./appliance-wizard.sh"

