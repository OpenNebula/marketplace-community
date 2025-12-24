# Nextcloud All-in-One Appliance

[Nextcloud All-in-One (AIO)](https://hub.docker.com/r/nextcloud/all-in-one) running on openSUSE Leap 15 with Docker. Includes Nextcloud Office, Talk, automatic updates and backups.

## Quick Start

1. **Export from Marketplace:**
   ```bash
   onemarketapp export 'Nextcloud All-in-One' nextcloud-suse --datastore default
   ```

2. **Instantiate the template:**
   ```bash
   onetemplate instantiate nextcloud-suse
   ```

3. **Attach network:**
   ```bash
   onevm nic-attach VM_ID --network VNET_ID
   ```

4. **Verify the container:**
   ```bash
   onevm ssh VM_ID
   docker ps
   ```

5. **Access web interface:** Open `https://VM_IP:8080` — the master password is shown on the AIO Welcome Screen.

> **Private network?** Use SSH port forwarding: `ssh -L 8080:VM_IP:8080 user@opennebula-host` then open `https://localhost:8080`

## Network Configuration Requirements

Nextcloud AIO needs to reach external container registries (ghcr.io) during startup to pull additional container images. Ensure your network is properly configured:

### 1. VNet DNS Configuration

Your OpenNebula virtual network must have valid DNS servers configured. The VM needs DNS to resolve external domains like `ghcr.io`.

```bash
# Check your VNet DNS configuration
onevnet show VNET_ID | grep DNS

# If DNS is missing or incorrect, update it:
onevnet update VNET_ID
# Add: DNS = "8.8.8.8 8.8.4.4"
```

### 2. Port Forwarding Rules (Private Networks)

If you're using NAT/port forwarding to expose the VM to the internet, ensure your DNAT rules **exclude traffic originating from the VM subnet**. Otherwise, outbound HTTPS traffic from the VM will loop back to itself.

> ⚠️ **These commands must be executed on the OpenNebula host (hypervisor), NOT inside the VM.**

**❌ Wrong (creates routing loop):**
```bash
# On OpenNebula host - DON'T do this!
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination VM_IP:443
```

**✅ Correct (excludes VM subnet):**
```bash
# On OpenNebula host
iptables -t nat -A PREROUTING -p tcp --dport 443 ! -s VM_SUBNET -j DNAT --to-destination VM_IP:443
```

Example for a VM at 172.16.100.2 with subnet 172.16.100.0/24:
```bash
# Run these commands on the OpenNebula HOST (not inside the VM)
# Port forwarding rules that don't break outbound traffic
iptables -t nat -A PREROUTING -p tcp --dport 443 ! -s 172.16.100.0/24 -j DNAT --to-destination 172.16.100.2:443
iptables -t nat -A PREROUTING -p tcp --dport 8443 ! -s 172.16.100.0/24 -j DNAT --to-destination 172.16.100.2:8443
iptables -t nat -A PREROUTING -p tcp --dport 8080 ! -s 172.16.100.0/24 -j DNAT --to-destination 172.16.100.2:8080

# Don't forget FORWARD rules
iptables -A FORWARD -p tcp -d 172.16.100.2 --dport 443 -j ACCEPT
iptables -A FORWARD -p tcp -d 172.16.100.2 --dport 8443 -j ACCEPT
iptables -A FORWARD -p tcp -d 172.16.100.2 --dport 8080 -j ACCEPT
```

To make these rules persistent across reboots (on Ubuntu/Debian host):
```bash
# On OpenNebula host
apt install iptables-persistent
iptables-save > /etc/iptables/rules.v4
```

### 3. Verify Outbound Connectivity

From inside the VM, verify it can reach external HTTPS services:
```bash
curl -I https://ghcr.io
```

If this times out or fails, check your DNS and iptables configuration.

## Domain Setup

When accessing the AIO interface for the first time, you'll need to enter a domain. Options:

| Option | Example | Notes |
|--------|---------|-------|
| **Your own domain** | `nextcloud.example.com` | Create DNS A record pointing to your server IP |
| **Wildcard DNS service** | `YOUR_IP.nip.io` | e.g., `51.158.111.100.nip.io` - no configuration needed |
| **Alternative wildcard DNS** | `YOUR-IP.sslip.io` | e.g., `51-158-111-100.sslip.io` - no configuration needed |

## Default Configuration

| Parameter | Default Value |
|-----------|---------------|
| Container Name | `nextcloud-aio-mastercontainer` |
| Ports | `80:80,8080:8080,8443:8443` |
| Environment | `SKIP_DOMAIN_VALIDATION=true` |
| Volumes | `/var/run/docker.sock:/var/run/docker.sock:ro,nextcloud_aio_mastercontainer:/mnt/docker-aio-config` |

> **Note about `SKIP_DOMAIN_VALIDATION`**: This is set to `true` by default to allow initial setup without a valid SSL certificate. Once you have a proper domain with SSL configured, you can set it to `false` for production use.

## Management Commands

```bash
docker ps                                              # View containers
docker logs nextcloud-aio-mastercontainer              # View logs
docker exec -it nextcloud-aio-mastercontainer bash     # Access shell
docker restart nextcloud-aio-mastercontainer           # Restart
```

## Technical Details

| | |
|-|-|
| **Base OS** | openSUSE Leap 15 |
| **Container** | [nextcloud/all-in-one:latest](https://hub.docker.com/r/nextcloud/all-in-one) |
| **Requirements** | 2GB RAM, 8GB disk minimum |

## Troubleshooting

### Container stuck at "Starting containers"
The AIO master container needs to pull additional images from ghcr.io. Check:
1. DNS is working: `host ghcr.io`
2. HTTPS is not blocked: `curl -I https://ghcr.io`
3. No iptables DNAT loop (see Network Configuration above)

### "Connection refused" when accessing web interface
1. Check container is running: `docker ps`
2. Check container logs: `docker logs nextcloud-aio-mastercontainer`
3. Verify ports are listening: `ss -tlnp | grep -E '(8080|8443)'`

## Resources

- [Nextcloud AIO Docker Hub](https://hub.docker.com/r/nextcloud/all-in-one) — Full documentation and configuration
- [Nextcloud AIO GitHub](https://github.com/nextcloud/all-in-one) — Source code and issues
