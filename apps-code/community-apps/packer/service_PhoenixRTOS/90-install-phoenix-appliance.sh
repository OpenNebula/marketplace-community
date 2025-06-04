#!/bin/bash

set -eux

mkdir -p /etc/one-appliance/service.d /etc/one-appliance/lib

cp /tmp/appliance.sh /etc/one-appliance/service.d/appliance.sh
cp /tmp/service.sh /etc/one-appliance/service
cp -r /tmp/lib/* /etc/one-appliance/lib/

chmod +x /etc/one-appliance/service
chmod +x /etc/one-appliance/service.d/appliance.sh

/etc/one-appliance/service install phoenix   || true

cat <<EOF > /etc/systemd/system/one-appliance.service
[Unit]
Description=Phoenix RTOS Appliance Configuration
After=network.target

[Service]
ExecStart=/etc/one-appliance/service configure
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable one-appliance.service
#systemctl start one-appliance.service

# Fallback: enable /etc/rc.local to trigger the appliance service at boot
cat <<'EOF' > /etc/rc.local
#!/bin/bash
systemctl start one-appliance.service
exit 0
EOF

chmod +x /etc/rc.local

# Enable rc-local compatibility service
cat <<'EOF' > /etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF

systemctl enable rc-local
