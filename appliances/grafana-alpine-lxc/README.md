# grafana-alpine-lxc

## Description

Grafana Dashboard running on Alpine Linux in an LXC container.

This appliance provides a lightweight, production-ready deployment of grafana optimized for edge and IoT environments.

## Requirements

- OpenNebula 6.10+ or 7.0+
- LXC-capable host with:
  - Architecture: aarch64
  - For contextless deployment: No special requirements
  - For standard context: iso9660 kernel module support

## Quick Start

1. Import appliance from OpenNebula Community Marketplace
2. Instantiate the VM template
3. Wait for deployment to complete
4. Access services:
   - Grafana Dashboard: http://<container-ip>:3000

## Configuration

### Contextualization Mode

This appliance is configured for **contextless** deployment:

- Uses DHCP for network configuration
- No iso9660 kernel module required
- Ideal for Arduino, Raspberry Pi, and embedded devices

### VM Resources

- **Memory**: 256MB
- **VCPUs**: 1
- **Disk**: 256MB

## Default Credentials

- **Username**: root
- **Password**: None (use SSH key-based authentication)
- **SSH Access**: Keys configured via OpenNebula context

## Services

The following services are pre-configured and running:

- **Grafana Dashboard** on port 3000

## Network Access

### For Embedded Devices (Arduino, Raspberry Pi)

Containers run on a private LXC bridge network. To access from other devices:

**Option 1: Tailscale Subnet Router (Recommended)**
```bash
# On LXC host:
sudo tailscale up --advertise-routes=10.0.3.0/24

# Approve route in Tailscale admin console
# Then access directly: http://10.0.3.x:<port>
```

**Option 2: Port Forwarding**
```bash
# On LXC host:
iptables -t nat -A PREROUTING -p tcp --dport <host-port> -j DNAT --to-destination <container-ip>:<service-port>
iptables -t nat -A POSTROUTING -j MASQUERADE
```

### For Standard Hosts

Access container directly via its IP address (visible in `onevm show`).

## Logs

- Service logs: `/var/log/<service>/`
- System logs: `/var/log/messages`

## Support

Report issues at: https://github.com/OpenNebula/one/issues

Use label: "Category: Marketplace"

## License

Community-contributed appliance. Service-specific licenses apply.

## Changelog

See CHANGELOG.md for version history.

## Author

Contributed by: Pablo

GitHub: @pablodelarco
