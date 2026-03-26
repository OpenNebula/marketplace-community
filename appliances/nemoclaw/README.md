# NemoClaw AI Agent Security Appliance

NemoClaw is NVIDIA's open-source AI agent security stack built on OpenClaw. It provides sandboxed execution environments with deny-by-default network policies and inference routing for AI agents. This appliance packages NemoClaw as a ready-to-deploy VM image for OpenNebula, with GPU passthrough support, Docker-based sandbox runtime, and NVIDIA inference routing pre-configured.

## Key Features

- **GPU Passthrough Support** - Leverage NVIDIA GPUs via OpenNebula PCI device assignment for local inference
- **Docker-Based Sandbox** - Isolated execution environments using Landlock, seccomp, and network namespaces
- **NVIDIA Inference Routing** - Connect to NVIDIA Endpoints API for cloud-based Nemotron model inference
- **Deny-By-Default Network Policies** - Sandboxes have no network access unless explicitly allowed
- **OpenShell TUI Monitoring** - Terminal-based monitoring interface for sandbox management
- **Graceful GPU Fallback** - Automatically detects GPU availability; falls back to cloud inference when no GPU is present

## Quick Start

1. Deploy the appliance from the OpenNebula Community Marketplace
2. SSH into the VM: `ssh root@VM_IP` (password: `opennebula`)
3. Get your API key at https://build.nvidia.com
4. Run: `nemoclaw onboard`
5. Follow the interactive setup wizard
6. Connect to your sandbox: `nemoclaw <sandbox-name> connect`

## Access Methods

| Method | Address             | Credentials          |
|--------|---------------------|----------------------|
| SSH    | `root@VM_IP`        | Password: `opennebula` |
| VNC    | OpenNebula console  | Via Sunstone UI      |

## Architecture

The appliance builds a layered stack on Ubuntu 24.04 LTS:

```
+--------------------------------------------------+
|  NemoClaw CLI + OpenShell Gateway                 |
+--------------------------------------------------+
|  NVIDIA Container Toolkit                         |
+--------------------------------------------------+
|  Docker Engine (CE)                               |
+--------------------------------------------------+
|  NVIDIA Driver 550-server                         |
+--------------------------------------------------+
|  Ubuntu 24.04 LTS + OpenNebula Contextualization  |
+--------------------------------------------------+
|  KVM / QEMU (OpenNebula hypervisor)               |
+--------------------------------------------------+
```

### Pre-installed Components

| Component                  | Version          |
|----------------------------|------------------|
| Docker Engine              | Latest stable    |
| NVIDIA Driver              | 550-server       |
| NVIDIA Container Toolkit   | Latest stable    |
| Node.js                    | 22.x LTS        |
| NemoClaw CLI               | 0.1.0 (alpha)   |

## GPU Requirements

GPU passthrough is optional. When no GPU is detected, NemoClaw uses cloud inference via NVIDIA Endpoints API.

### Host-Side Prerequisites (for GPU passthrough)

1. **IOMMU enabled** in BIOS and kernel:
   - Intel: `intel_iommu=on iommu=pt` in kernel command line
   - AMD: `amd_iommu=on` in kernel command line
2. **vfio-pci driver** loaded for the GPU device
3. **OpenNebula PCI device assignment** configured with vendor `10de` (NVIDIA)
4. **Blacklist nouveau driver** on the host to avoid conflicts

Refer to the [OpenNebula GPU Passthrough documentation](https://docs.opennebula.io/7.0/product/cluster_configuration/hosts_and_clusters/nvidia_gpu_passthrough/) for detailed setup instructions.

## VM Resources

| Resource | Minimum   | Recommended |
|----------|-----------|-------------|
| CPU      | 2 vCPU    | 4 vCPU      |
| RAM      | 8 GB      | 16 GB       |
| Disk     | 40 GB     | 80 GB       |

## Monitoring

- **OpenShell TUI**: Run `openshell term` for a terminal-based monitoring interface
- **Sandbox Status**: Run `nemoclaw <sandbox-name> status` to check sandbox state
- **Docker Containers**: Run `docker ps` to view running containers
- **GPU Status**: Run `nvidia-smi` to check GPU utilization (when GPU is available)

## Troubleshooting

### No GPU detected

- Verify GPU passthrough is configured on the OpenNebula host
- Check that IOMMU is enabled: `dmesg | grep -i iommu`
- Confirm the GPU is assigned to the VM in OpenNebula template
- Run `lspci | grep -i nvidia` to verify the GPU is visible to the VM
- NemoClaw will work without a GPU using cloud inference

### Docker not running

```bash
systemctl status docker
systemctl start docker
journalctl -u docker --no-pager -n 50
```

### NemoClaw CLI not found

```bash
which nemoclaw
# If missing, reinstall:
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
```

### Sandbox fails to start

```bash
nemoclaw <sandbox-name> logs
docker logs $(docker ps -aq --filter name=openshell) 2>/dev/null
```

## Documentation

- [NVIDIA NemoClaw Documentation](https://docs.nvidia.com/nemoclaw/latest/)
- [NVIDIA NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw)
- [OpenClaw Documentation](https://openclawapi.org)
- [OpenNebula GPU Passthrough](https://docs.opennebula.io/7.0/product/cluster_configuration/hosts_and_clusters/nvidia_gpu_passthrough/)

## Important Notes

- **Alpha Software**: NemoClaw is currently in alpha. APIs and behavior may change between releases. Pin your NemoClaw version in production environments.
- **API Key Required**: You must obtain an NVIDIA API key from https://build.nvidia.com to use cloud inference.
- **Default Password**: The default root password is `opennebula`. Change it after first login for security.
- **Version**: This appliance packages NemoClaw 0.1.0 (alpha) on Ubuntu 24.04 LTS.
