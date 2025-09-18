#!/usr/bin/env bash
exec 1>&2
set -eux -o pipefail

gawk -i inplace -f- /etc/ssh/sshd_config <<'EOF'
BEGIN { update = "PasswordAuthentication no" }
/^[#\s]*PasswordAuthentication\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
