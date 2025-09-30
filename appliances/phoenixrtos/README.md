# Phoenix RTOS Appliance

[Phoenix RTOS](https://phoenix-rtos.org/) is a scalable real-time operating system for IoT. This appliance provides Phoenix RTOS running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**Phoenix RTOS capabilities:**
- Real-time microkernel architecture
- POSIX-compliant API
- Small memory footprint (starting from 32KB)
- Support for multiple architectures (IA32, ARMv7, ARMv8, RISC-V)
- Built-in networking stack
- BusyBox shell environment
- Modular design with loadable drivers

**Appliance features:**
- **Automatic VNC login** - no password required for VNC access
- **SSH key authentication** from OpenNebula context
- Ready-to-use Phoenix RTOS environment running in Docker
- Web-based Phoenix RTOS interface on port 8080
- Configurable container parameters

## Download

The Phoenix RTOS appliance can be downloaded from the OpenNebula Community Marketplace.

## Requirements

- OpenNebula 6.10 or later
- KVM hypervisor
- At least 2GB RAM and 2 vCPU recommended
- Network connectivity for Docker image downloads

## Quick Start

The default template will instantiate a Phoenix RTOS instance running in a Docker container with interactive access.

Steps to deploy a Phoenix RTOS instance:

1. Download the Phoenix RTOS appliance from the OpenNebula Community Marketplace. This will download the VM template and the image for the OS.

   ```
   $ onemarketapp export 'Phoenix RTOS' PhoenixRTOS --datastore default
   ```

2. Adjust the VM template as desired (i.e. CPU, MEMORY, disk, network).

3. Instantiate Phoenix RTOS template:
   ```
   $ onetemplate instantiate PhoenixRTOS
   ```
   This will prompt the user for the contextualization parameters.

4. Access your new Phoenix RTOS instance:

   **Via VNC (Automatic Login):**
   - Connect to `vnc://VM_IP:5900`
   - No password required - automatic login enabled
   - Phoenix RTOS container starts automatically

   **Via SSH (Key Authentication):**
   ```
   $ ssh root@<vm-ip-address>
   $ docker exec -it phoenix-rtos-one /bin/bash
   ```

   **Via Web Interface:**
   - Open `http://VM_IP:8080` in your browser
   - Access Phoenix RTOS web interface

## Configuration Parameters

The appliance supports the following contextualization parameters:

- **ONEAPP_PHOENIXRTOS_PORTS**: Port mappings for the Phoenix RTOS container (default: 8080:8080)
- **ONEAPP_PHOENIXRTOS_VOLUMES**: Volume mappings for persistent data storage
- **ONEAPP_PHOENIXRTOS_ENV_VARS**: Environment variables to pass to the Phoenix RTOS container
- **ONEAPP_PHOENIXRTOS_COMMAND**: Custom command to run in the Phoenix RTOS container
- **ONEAPP_DOCKER_REGISTRY_URL**: Custom Docker registry URL (optional)
- **ONEAPP_DOCKER_REGISTRY_USER**: Docker registry username (optional)
- **ONEAPP_DOCKER_REGISTRY_PASSWORD**: Docker registry password (optional)

## Phoenix RTOS Usage

Once inside the Phoenix RTOS container, you can:

1. **Explore the system**: Use standard Unix commands like `ls`, `ps`, `cat`, etc.
2. **Access the Phoenix shell**: The `(psh)%` prompt provides access to Phoenix RTOS-specific commands
3. **Run applications**: Execute Phoenix RTOS applications and utilities
4. **Network operations**: Use built-in networking tools like `ping`, `ifconfig`, `nc`
5. **Development**: Compile and run your own Phoenix RTOS applications

Example Phoenix RTOS commands:
```bash
(psh)% help          # Show available commands
(psh)% ps            # List running processes
(psh)% mem           # Show memory usage
(psh)% ifconfig      # Configure network interfaces
(psh)% ping 8.8.8.8  # Test network connectivity
```

## Troubleshooting

### Container not starting
If the Phoenix RTOS container fails to start, check:
- Docker service status: `systemctl status docker`
- Container logs: `docker logs phoenix-rtos-one`
- Available resources: `free -h` and `df -h`

### Network issues
- Verify network configuration: `ip addr show`
- Check Docker network: `docker network ls`
- Test connectivity: `ping google.com`

### Performance issues
- Increase VM resources (CPU/Memory) if Phoenix RTOS appears slow
- Monitor resource usage: `top` or `htop`

## Support

For Phoenix RTOS specific questions, visit:
- [Phoenix RTOS Documentation](https://phoenix-rtos.org/documentation/)
- [Phoenix RTOS GitHub](https://github.com/phoenix-rtos)

For OpenNebula appliance issues:
- [OpenNebula Community Forum](https://forum.opennebula.org/)
- [OpenNebula Documentation](https://docs.opennebula.org/)
