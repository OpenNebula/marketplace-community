#!/usr/bin/env bash

# Configures critical settings for OpenSSH server.
# This script reverts the insecure SSH settings that were enabled during build.

exec 1>&2
set -eux -o pipefail

if command -v gawk &> /dev/null; then
    gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "PasswordAuthentication no" }
/^[#\s]*PasswordAuthentication\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

    gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "PermitRootLogin without-password" }
/^[#\s]*PermitRootLogin\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

    gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "UseDNS no" }
/^[#\s]*UseDNS\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF
else
    # Fallback without gawk
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
    sed -i 's/^#*UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
    # Add if not present
    grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
    grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
    grep -q "^UseDNS" /etc/ssh/sshd_config || echo "UseDNS no" >> /etc/ssh/sshd_config
fi

sync
