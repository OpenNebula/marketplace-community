#!/bin/bash

# Redirect output to a log file for debugging
exec > /root/startup.log 2>&1

# Function to show progress in VNC (tty1)
progress() {
    local message=$1
    echo -e "\e[1;32m$message\e[0m" > /dev/tty1
}

# Ensure we're in the VNC-visible console (switch to tty1)
chvt 1
clear > /dev/tty1

# Hide the login prompt until everything is ready
systemctl stop getty@tty1.service
systemctl mask getty@tty1.service

progress "Updating network configuration..."
sed -i 's/^#DNS=/DNS=8.8.8.8 1.1.1.1/' /etc/systemd/resolved.conf
sed -i 's/^#FallbackDNS=/FallbackDNS=8.8.4.4 9.9.9.9/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

progress "Updating system and installing prerequisites..."
apt-get update
apt-get install -y ca-certificates curl gnupg

progress "Setting up IoT Lab environment..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

progress "Installing Phoenix RTOS..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

progress "Deploying Phoenix RTOS..."
docker pull pablodelarco/phoenix-rtos-one:latest
docker run --rm -it --network host pablodelarco/phoenix-rtos-one

progress "Re-enabling login prompt..."
systemctl unmask getty@tty1.service
systemctl start getty@tty1.service

progress "Setting up auto-login for root user..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat <<EOF > /etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I linux
EOF

# Reload systemd to apply auto-login changes
systemctl daemon-reexec
systemctl restart getty@tty1.service

progress "Ensuring root password is set (optional, only needed if login fails)..."
echo 'root:root' | chpasswd

# Run the container interactively inside the terminal on login
echo 'clear' >> /root/.bash_profile
echo 'docker run --rm -it --network host pablodelarco/phoenix-rtos-one' >> /root/.bash_profile

progress "Setup complete. The system will now start automatically..."
