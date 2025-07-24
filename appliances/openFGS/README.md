# Open5GS (OpenFGS) Appliance - ONEedge5G

## Overview

The Open5GS appliance provides a complete 5G Standalone (SA) Core Network implementation based on the Open5GS project. This appliance delivers all essential 5G core network functions in a single, optimized virtual machine, enabling rapid deployment of 5G core infrastructure in OpenNebula environments.

Built on Ubuntu 24.04 LTS, the appliance includes a comprehensive set of 5G core network functions, a web-based management interface for subscriber management, and automatic network optimization for seamless integration with 5G radio access networks.

## Release Notes

The Open5GS appliance is based on Ubuntu 24.04 LTS (for x86-64).

| Component | Version |
| --------- | ------- |
| Open5GS | v2.7.6 |
| MongoDB | v8.0 |


## Quick Start

### Prerequisites

- **OpenNebula Environment**: Functional OpenNebula cloud platform
- **Hardware Requirements**:
  - 4 vCPUs
  - 16 GB RAM
  - 40 GB disk space
- **Network Configuration**: Proper network connectivity for N2/N3 interfaces
- **Browser Access**: Modern web browser for WebUI management

### Deployment Steps

1. **Import the Appliance Image**
   ```bash
   # Upload the Open5GS appliance image to OpenNebula
   oneimage create --name "Open5GS" --path service_openFGS.qcow2 --driver qcow2
   ```

2. **Create VM Template**
   ```yaml
   CONTEXT=[
     NETWORK="YES",
     ONEAPP_OPEN5GS_MCC="999",
     ONEAPP_OPEN5GS_MNC="75",
     ONEAPP_OPEN5GS_N2_IP="10.0.3.2",
     ONEAPP_OPEN5GS_N3_IP="10.0.3.2",
     ONEAPP_OPEN5GS_TAC="1",
     ONEAPP_OPEN5GS_WEBUI_IP="0.0.0.0",
     ONEAPP_OPEN5GS_WEBUI_PORT="3000",
     SSH_PUBLIC_KEY="$USER[SSH_PUBLIC_KEY]"
   ]
   CPU="4"
   MEMORY="16384"
   DISK=[
     IMAGE_ID="<OPEN5GS_IMAGE_ID>",
     SIZE="30720"
   ]
   ```

3. **Deploy the VM**
   ```bash
   # Instantiate the VM
   onetemplate instantiate <template_id>
   ```

4. **Access WebUI Management**
   ```bash
   # Open browser and navigate to:
   http://<vm_ip>:3000
   
   # Default credentials:
   # Username: admin
   # Password: 1423
   ```

5. **Configure Subscribers**
   - Log into the WebUI
   - Navigate to Subscriber Management
   - Add UE subscribers with IMSI, K, OPc values
   - Configure APN and QoS profiles as needed

6. **Connect gNodeB**
   - Configure gNodeB to connect to AMF at the N2 interface IP
   - Verify N2 and N3 interface connectivity
   - Monitor connection status through logs

### Configuration Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `ONEAPP_OPEN5GS_MCC` | Mobile Country Code | `999` | No |
| `ONEAPP_OPEN5GS_MNC` | Mobile Network Code | `75` | No |
| `ONEAPP_OPEN5GS_N2_IP` | N2 interface IP address | `10.0.3.2` | No |
| `ONEAPP_OPEN5GS_N3_IP` | N3 interface IP address | `10.0.3.2` | No |
| `ONEAPP_OPEN5GS_TAC` | Tracking Area Code | `1` | No |
| `ONEAPP_OPEN5GS_WEBUI_IP` | WebUI bind IP address | `0.0.0.0` | No |
| `ONEAPP_OPEN5GS_WEBUI_PORT` | WebUI HTTP port | `3000` | No |


## Features

### Complete 5G Core Network Functions

- **Access and Mobility Management Function (AMF)**
  - UE registration and authentication
  - Mobility management and tracking
  - Session management coordination
  - N2 interface towards gNodeB

- **Session Management Function (SMF)**
  - PDU session management
  - QoS policy enforcement
  - UPF selection and control
  - N4 interface towards UPF

- **User Plane Function (UPF)**
  - Packet routing and forwarding
  - Traffic inspection and reporting
  - QoS enforcement
  - N3 interface towards gNodeB, N6 towards data networks

- **Authentication Server Function (AUSF)**
  - UE authentication procedures
  - Security context management
  - Integration with UDM for subscriber data

- **Unified Data Management (UDM)**
  - Subscriber data management
  - Authentication credential processing
  - User consent management

- **Unified Data Repository (UDR)**
  - Centralized data storage
  - Subscriber profile management
  - Policy data storage

- **Policy Control Function (PCF)**
  - Policy rule provisioning
  - QoS control and charging
  - Application function interaction

- **Network Repository Function (NRF)**
  - Service discovery and registration
  - NF profile management
  - Load balancing support

- **Binding Support Function (BSF)**
  - PCF discovery and selection
  - Binding information management

- **Network Slice Selection Function (NSSF)**
  - Network slice selection
  - Slice-specific AMF selection

### Web-Based Management Interface

- **Subscriber Management**
  - Add, edit, and delete UE subscribers
  - IMSI, K, OPc, and AMF configuration
  - APN and slice configuration
  - Real-time subscriber status monitoring

- **Network Configuration**
  - PLMN configuration (MCC/MNC)
  - TAC and cell configuration
  - QoS profile management
  - Policy rule configuration

### Database and Storage

- **MongoDB 8.0 Backend**
  - High-performance document database
  - Automatic replication support
  - Scalable storage architecture
  - Backup and recovery capabilities

- **Data Management**
  - Subscriber profile storage
  - Session state management
  - Policy data persistence
  - Configuration backup

### Network Optimization

- **Automatic IP Forwarding**
  - Kernel IP forwarding enabled
  - Optimized routing tables
  - NAT configuration for UE traffic
  - Multi-interface support

- **Performance Tuning**
  - Network buffer optimizations
  - Connection pooling
  - Memory management optimization
  - CPU affinity configuration

- **Interface Configuration**
  - N2 interface (AMF ↔ gNodeB)
  - N3 interface (UPF ↔ gNodeB)
  - N4 interface (SMF ↔ UPF)
  - N6 interface (UPF ↔ Data Network)

### Service Management

- **Systemd Integration**
  - Individual services for each NF
  - Automatic startup and dependency management
  - Service health monitoring
  - Graceful shutdown procedures

- **Logging and Monitoring**
  - Comprehensive logging for all NFs
  - Centralized log management
  - Real-time service monitoring
  - Performance metrics collection

- **Configuration Management**
  - YAML-based configuration files
  - Dynamic configuration updates
  - Template-based deployment
  - Validation and error checking

### Integration and Compatibility

- **Standards Compliance**
  - 3GPP Release 16/17 compliance
  - Service-Based Architecture (SBA)
  - RESTful API interfaces
  - Standard network interfaces

- **Interoperability**
  - Compatible with standard gNodeBs
  - Support for multiple vendors
  - Standard protocol implementations
  - Flexible configuration options

- **OpenNebula Integration**
  - Native context support
  - Template-based deployment
  - Automatic network configuration
  - Resource scaling capabilities

### Monitoring and Troubleshooting

- **Comprehensive Logging**
  - Individual NF logs
  - System-wide logging
  - Error tracking and reporting
  - Performance monitoring

- **Diagnostic Tools**
  - Network connectivity testing
  - Service health checks
  - Performance benchmarking
  - Configuration validation

- **Management Commands**
  ```bash
  # Service status monitoring
  systemctl status open5gs-*
  
  # Real-time log monitoring
  journalctl -u open5gs-amfd -f
  
  # Configuration verification
  cat /etc/open5gs/*.yaml
  
  # Database status
  systemctl status mongod
  ```

This appliance provides a complete, production-ready 5G core network solution that can be easily deployed and managed in OpenNebula environments, offering comprehensive functionality for 5G network operators, researchers, and developers.