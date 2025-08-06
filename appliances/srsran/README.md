# srsRAN Project Appliance - ONEedge5G

## Overview

srsRAN Project is an open-source O-RAN 5G software radio suite that implements complete 5G New Radio (NR) functionalities with support for disaggregated deployments. This appliance provides an optimized OpenNebula deployment solution for srsRAN Project components, enabling easy deployment of 5G base station infrastructure in virtualized environments.

The appliance supports three main deployment modes:
- **gNodeB**: Monolithic 5G base station (CU+DU combined)
- **CU**: Central Unit
- **DU**: Distributed Unit

Built on Ubuntu 24.04 LTS, the appliance includes comprehensive optimizations for real-time performance, high-throughput packet processing, and precise timing synchronization essential for 5G deployments.

## Release Notes

The srsRAN Project appliance is based on Ubuntu 24.04 LTS (for x86-64).

| Component | Version |
| --------- | ------- |
| srsRAN Project | release_24_10_1 |
| DPDK | 23.11 |
| Intel iavf driver | 4.13.3 |
| LinuxPTP | 4.3 |
| RT Kernel | 6.8.2-rt10-preempt-rt |


## Quick Start

### Prerequisites

- **OpenNebula Environment**: Functional OpenNebula cloud platform
- **Hardware Requirements**: 
  - 32 vCPUs
  - 32 GB RAM
  - 80 GB disk space
  - Intel E810 NIC (for PCI passthrough and PTP support)
- **Network Configuration**: Proper network setup for 5G interfaces

### Deployment Steps

1. **Import the Appliance Image**
   ```bash
   # Upload the srsRAN appliance image to OpenNebula
   oneimage create --name "srsRAN-v1.4.0" --path service_srsRAN.qcow2 --driver qcow2
   ```

2. **Create VM Template**
   ```yaml
   CONTEXT=[
    ONEAPP_SRSRAN_MODE = "gnb",                    # Deployment mode: gnb, cu, du
    ONEAPP_SRSRAN_MCC = "999",                     # Mobile Country Code
    ONEAPP_SRSRAN_MNC = "75",                      # Mobile Network Code
    ONEAPP_SRSRAN_TAC = "1",                       # Tracking Area Code
    ONEAPP_SRSRAN_PCI = "69",                      # Physical Cell Identity
    ONEAPP_SRSRAN_DL_ARFCN = "656668",             # Downlink ARFCN
    ONEAPP_SRSRAN_BAND = "n77",                    # NR Band
    ONEAPP_SRSRAN_CHANNEL_BW_MHZ = "100",          # Channel Bandwidth
    ONEAPP_SRSRAN_ENABLE_DPDK = "YES",             # Enable DPDK
    ONEAPP_SRSRAN_AMF_IPV4 = "10.0.3.2",           # AMF IP address
    ONEAPP_SRSRAN_NIC_PCI_ADDR = "0000:01:01.0",   # NIC PCI address
    ONEAPP_SRSRAN_RU_MAC = "e8:c7:4f:25:89:41",    # RU MAC address
    NETWORK = "YES",
    SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]"
   ]
   CPU="32"
   MEMORY="32768"
   DISK=[
     IMAGE_ID="<SRSRAN_IMAGE_ID>",
     SIZE="51200"
   ]
   ```

3. **Deploy the VM**
   ```bash
   # Instantiate the VM
   onetemplate instantiate <template_id>
   ```

4. **Verify Deployment**
   ```bash
   # SSH into the VM and check services
   ssh root@<vm_ip>
   systemctl status srsran-gnb
   journalctl -u srsran-gnb -f
   ```

5. **Connect to 5G Core**
   - Ensure AMF is accessible at the configured IP address
   - Verify N2 and N3 interface connectivity
   - Check Open Fronthaul connection to Radio Unit

### Configuration Parameters

| Parameter | Description | Default | Valid Values |
|-----------|-------------|---------|-------------|
| `ONEAPP_SRSRAN_MODE` | Deployment mode | `gnb` | `gnb`, `cu`, `du` |
| `ONEAPP_SRSRAN_MCC` | Mobile Country Code | `999` | 3-digit code |
| `ONEAPP_SRSRAN_MNC` | Mobile Network Code | `75` | 2-3 digit code |
| `ONEAPP_SRSRAN_TAC` | Tracking Area Code | `1` | 1-65535 |
| `ONEAPP_SRSRAN_PCI` | Physical Cell Identity | `69` | 0-1007 |
| `ONEAPP_SRSRAN_DL_ARFCN` | Downlink ARFCN | `656668` | NR ARFCN |
| `ONEAPP_SRSRAN_BAND` | NR Band | `n77` | `n1`, `n3`, `n7`, `n77`, `n78` |
| `ONEAPP_SRSRAN_ENABLE_DPDK` | Enable DPDK | `YES` | `YES`, `NO` |
| `ONEAPP_SRSRAN_COMMON_SCS` | Subcarrier Spacing | `30` | `15`, `30`, `60` |
| `ONEAPP_SRSRAN_CHANNEL_BW_MHZ` | Channel Bandwidth | `100` | `5`, `10`, `15`, `20`, `25`, `30`, `40`, `50`, `60`, `70`, `80`, `90`, `100` |
| `ONEAPP_SRSRAN_NR_CELLS` | Number of cells | `1` | 1-8 |
| `ONEAPP_SRSRAN_AMF_IPV4` | AMF IP address | `10.0.3.2` | Valid IPv4 |
| `ONEAPP_SRSRAN_NIC_PCI_ADDR` | NIC PCI address | `0000:01:01.0` | PCI address |
| `ONEAPP_SRSRAN_RU_MAC` | RU MAC address | `e8:c7:4f:25:89:41` | MAC address |

## Features

### Core Capabilities

- **Complete 5G NR Implementation**: Full support for 5G New Radio specifications
- **Split 7.2 Architecture**: Disaggregated deployments with Open Fronthaul support
- **Multiple Deployment Modes**: Flexible gNodeB, CU, and DU configurations
- **Production Ready**: Optimized for real-world 5G network deployments

### Performance Optimizations

- **Real-Time Kernel**: Linux 6.8.2 with RT-PREEMPT patch (6.8.2-rt10)
  - Ultra-low latency for time-critical 5G processing
  - Deterministic performance for Open Fronthaul synchronization
  - 1000Hz timer frequency for microsecond precision
  - Automatic real-time group configuration

- **DPDK Support**: High-performance packet processing
  - DPDK 23.11 compiled from source
  - Dual installation (base + DPDK versions)
  - igb_uio driver for Intel NICs
  - Automatic hugepages configuration (2GB of 1G hugepages)
  - Runtime selection via configuration

- **Network Optimizations**:
  - DRM KMS polling disabled for reduced latency
  - Network buffer optimizations (33MB buffers)
  - RT priority elevation for critical kernel threads
  - Intel iavf driver v4.13.3 with PTP support

### Timing and Synchronization

- **VM Clock Synchronization**: Precise timing for 5G applications
  - LinuxPTP 4.3 with PHC2SYS daemon
  - Automatic ptp_kvm module configuration
  - Dynamic PTP device detection
  - Hardware PTP clock synchronization

- **PTP Support**: IEEE 1588 Precision Time Protocol
  - Sub-microsecond synchronization accuracy
  - Compatible with Intel E810 NICs
  - Automatic service configuration

### Management and Monitoring

- **Systemd Integration**: Complete service management
  - Automatic service creation based on deployment mode
  - Comprehensive logging and monitoring
  - Service dependency management
  - Graceful startup and shutdown procedures

- **Configuration Management**:
  - YAML-based configuration files
  - Production-ready templates included
  - Dynamic configuration via OpenNebula context
  - Comprehensive parameter validation

- **Troubleshooting Tools**:
  - Detailed logging for all components
  - Performance monitoring utilities
  - Network diagnostic tools
  - Real-time latency testing (cyclictest)

### Advanced Features

- **Open Fronthaul (OFH)**: Complete Split 7.2 support
  - eCPRI transport protocol
  - Production Radio Unit compatibility
  - LiteON RU configuration templates
  - Flexible RU MAC address configuration

- **Multi-Cell Support**: Scalable deployments
  - Up to 8 NR cells per deployment
  - Configurable cell parameters
  - Load balancing capabilities
  - Inter-cell coordination

- **Security Features**:
  - SSH key-based authentication
  - Secure service communication
  - Network isolation support
  - Firewall integration

### Build and Deployment

- **Intelligent Build System**:
  - Pre-compiled RT kernel package support
  - 70-80% build time reduction with pre-built packages
  - Automatic dependency resolution
  - Comprehensive build verification

- **OpenNebula Integration**:
  - Native context support
  - User input validation
  - Template-based deployment
  - Automatic network configuration

- **Monitoring and Logging**:
  - Comprehensive appliance deployment logs
  - Real-time service monitoring
  - Performance metrics collection
  - Configuration status reporting

This appliance provides a complete solution for deploying srsRAN Project in OpenNebula environments, with extensive optimizations for performance, reliability, and ease of management.