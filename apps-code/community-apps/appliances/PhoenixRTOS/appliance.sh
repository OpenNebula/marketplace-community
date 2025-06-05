#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------
ONE_SERVICE_NAME='Phoenix-RTOS Appliance'
ONE_SERVICE_VERSION='0.1.2'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Ubuntu Jammy VM that auto-installs Phoenix-RTOS container'
ONE_SERVICE_RECONFIGURABLE=false

# ------------------------------------------------------------------------------
# Contextualization parameters
# ------------------------------------------------------------------------------
ONE_SERVICE_PARAMS=(
  'PASSWORD'       'configure'  'Password for root user (if used)'     'O|text'
  'SSH_PUBLIC_KEY' 'configure'  'SSH key for root login'               'O|text64'
  'START_SCRIPT'   'configure'  'Script to run at first boot'          'O|text64'
  'GROW_ROOTFS'    'configure'  'Automatically grow root filesystem'   'O|boolean'
)

# ------------------------------------------------------------------------------
# Context defaults
# ------------------------------------------------------------------------------
PASSWORD="${PASSWORD:-root}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
START_SCRIPT="${START_SCRIPT:-}"
GROW_ROOTFS="${GROW_ROOTFS:-YES}"

# ------------------------------------------------------------------------------
# Help & noop install
# ------------------------------------------------------------------------------
service_help() {
  cat <<EOF >/dev/tty1
Phoenix-RTOS Appliance
Stages:
  install    - not used (built into image)
  configure  - runs once at first boot
EOF
}

service_install() {
  echo "[Phoenix-RTOS] install stage not required." >/dev/tty1 || true
}

# ------------------------------------------------------------------------------
# Spinner (tty1) while work happens in background
# ------------------------------------------------------------------------------
spin() {
  local pid=$1
  local delay=0.2
  local str='|/-\'
  local i=0
  printf "\rLoading Phoenix-RTOS %c" "${str:i:1}" >/dev/tty1
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#str} ))
    printf "\rLoading Phoenix-RTOS %c" "${str:i:1}" >/dev/tty1
    sleep "$delay"
  done
  printf "\rLoading Phoenix-RTOS done\n" >/dev/tty1
}

# ------------------------------------------------------------------------------
# Configure — runs once at first boot
# ------------------------------------------------------------------------------
service_configure() {
  # prevent re-running
  local SENTINEL=/var/lib/one-context/phoenix-configured
  [[ -e "$SENTINEL" ]] && exit 0
  touch "$SENTINEL"

  # all verbose logs go to this file
  exec > /root/startup.log 2>&1

  # this function does all the real work
  perform() {
    # 1) set root password if non-default
    if [[ -n "$PASSWORD" && "$PASSWORD" != "root" ]]; then
      echo "root:${PASSWORD}" | chpasswd
    fi

    # 2) install SSH key
    if [[ -n "$SSH_PUBLIC_KEY" ]]; then
      mkdir -p /root/.ssh
      echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
    fi

    # 3) run START_SCRIPT if given
    if [[ -n "$START_SCRIPT" ]]; then
      echo "$START_SCRIPT" > /tmp/start_script.sh
      chmod +x /tmp/start_script.sh
      /tmp/start_script.sh || true
    fi

    # 4) grow rootfs if requested
    if [[ "$GROW_ROOTFS" =~ ^(yes|YES)$ ]]; then
      growpart /dev/vda 1 || true
      resize2fs /dev/vda1   || true
    fi

    # 5) hard-code DNS
    sed -i 's/^#\?DNS=.*/DNS=8.8.8.8 1.1.1.1/'        /etc/systemd/resolved.conf
    sed -i 's/^#\?FallbackDNS=.*/FallbackDNS=8.8.4.4 9.9.9.9/' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved

    # 6) launch Phoenix-RTOS container if not already running
    docker inspect phoenix-rtos >/dev/null 2>&1 \
      || docker run -d --name phoenix-rtos --restart=always --network host \
           pablodelarco/phoenix-rtos-one:latest

    # 7) configure auto-login on tty1
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat <<CONF >/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I linux
CONF
    systemctl daemon-reload
    systemctl unmask getty@tty1.service || true
    systemctl restart getty@tty1.service

    # 8) make console drop straight into the container
    cat <<'EOF' >> /root/.bash_profile

# auto-exec Phoenix-RTOS container on console login
clear
exec docker run --rm -it --network host pablodelarco/phoenix-rtos-one:latest
EOF
  }

  # spin off the work, run spinner on tty1
  perform & pid=$!
  spin $pid
  wait $pid
}

# ------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------
case "${1:-help}" in
  install)   service_install ;;
  configure) service_configure ;;
  help|*)    service_help ;;
esac
