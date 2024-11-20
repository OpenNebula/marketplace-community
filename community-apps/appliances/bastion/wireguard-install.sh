#!/bin/bash
#
# https://github.com/Nyr/wireguard-install
#
# Copyright (c) 2020 Nyr. Released under the MIT License.

ip="$1"
port="$2"
allowed_nets="$3"
dns="$4"
client="$5"

new_client_setup () {
	# Given a list of the assigned internal IPv4 addresses, obtain the lowest still
	# available octet. Important to start looking at 2, because 1 is our gateway.
	octet=2
	while grep AllowedIPs /etc/wireguard/wg0.conf | cut -d "." -f 4 | cut -d "/" -f 1 | grep -q "^$octet$"; do
		(( octet++ ))
	done
	# Don't break the WireGuard configuration in case the address space is full
	if [[ "$octet" -eq 255 ]]; then
		echo "253 clients are already configured. The WireGuard internal subnet is full!"
		exit
	fi
	key=$(wg genkey)
	psk=$(wg genpsk)
	# Configure client in the server
	cat << EOF >> /etc/wireguard/wg0.conf
# BEGIN_PEER $client
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.7.0.$octet/32
# END_PEER $client
EOF
	# Create client configuration
	cat << EOF > ~/"$client".conf
[Interface]
Address = 10.7.0.$octet/24
DNS = $dns
PrivateKey = $key

[Peer]
PublicKey = $(grep PrivateKey /etc/wireguard/wg0.conf | cut -d " " -f 3 | wg pubkey)
PresharedKey = $psk
AllowedIPs = $allowed_nets
Endpoint = $(grep '^# ENDPOINT' /etc/wireguard/wg0.conf | cut -d " " -f 3):$(grep ListenPort /etc/wireguard/wg0.conf | cut -d " " -f 3)
PersistentKeepalive = 25
EOF
}

if [[ ! -e /etc/wireguard/wg0.conf ]]; then

	echo
	echo "WireGuard installation is ready to begin."

    apt-get update
    apt-get install -y wireguard

	# Generate wg0.conf
	cat << EOF > /etc/wireguard/wg0.conf
# Do not alter the commented lines
# They are used by wireguard-install
# ENDPOINT ${ip}

[Interface]
Address = 10.7.0.1/24
PrivateKey = $(wg genkey)
ListenPort = ${port}

PostUp = nft add rule inet wireguard input udp dport ${port} counter accept
PostUp = nft add rule inet wireguard forward iifname %i counter accept
PostUp = nft add rule inet wireguard forward oifname %i counter accept
PostUp = nft add rule inet wireguard forward ct state related,established counter accept
PostDown = nft delete rule inet wireguard input udp dport ${port} counter accept
PostDown = nft delete rule inet wireguard forward iifname %i counter accept
PostDown = nft delete rule inet wireguard forward oifname %i counter accept
PostDown = nft delete rule inet wireguard forward ct state related,established counter accept
EOF
# PostUp = iptables -I input -p udp --dport ${port} -j ACCEPT
# PostUp = iptables -I forward -o %i -j ACCEPT
# PostUp = iptables -I forward -i %i -j ACCEPT
# PostUp = iptables -I forward -m state --state RELATED,ESTABLISHED -j ACCEPT
# PostDown = iptables -D input -p udp --dport ${port} -j ACCEPT
# PostDown = iptables -D forward -o %i -j ACCEPT
# PostDown = iptables -D forward -i %i -j ACCEPT
# PostDown = iptables -D forward -m state --state RELATED,ESTABLISHED -j ACCEPT

	chmod 600 /etc/wireguard/wg0.conf

	# Generates the custom client.conf
	new_client_setup
	# Enable and start the wg-quick service
	systemctl enable --now wg-quick@wg0.service

	echo
	echo "Finished!"
	echo
	echo "The client configuration is available in:" ~/"$client.conf"
	echo "New clients can be added by running this script again."
fi