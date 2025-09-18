# Generic Docker Appliance Framework for OpenNebula Community Marketplace

This document describes a generic framework for creating Docker-based appliances for the OpenNebula Community Marketplace. The framework provides a reusable, streamlined method for packaging any Docker image as an OpenNebula appliance with Ubuntu 22.04 LTS as the base OS.

## Overview

The Generic Docker Appliance Framework simplifies the process of creating OpenNebula appliances that run Docker containers. It provides:

- **Automatic Docker installation and configuration**
- **Configurable container parameters** (ports, volumes, environment variables)
- **Flexible restart policies and network modes**
- **Privileged mode support when needed**
- **Comprehensive logging and monitoring**
- **Easy customization for specific applications**

## Framework Components

### 1. Generic Docker Appliance (`appliances/docker-generic/`)

The base framework that provides all Docker functionality:

- `appliance.sh` - Main script with Docker installation and container management
- `metadata.yaml` - Configuration metadata for testing and deployment
- Configurable parameters for any Docker image

### 2. Packer Configuration (`apps-code/community-apps/packer/docker-generic/`)

Build system configuration:

- `docker-generic.pkr.hcl` - Main Packer build configuration
- `variables.pkr.hcl` - Build variables
- `common.pkr.hcl` - Common Packer settings
- Build scripts for SSH and context configuration

### 3. Example Implementation: Phoenix RTOS (`appliances/phoenixrtos/`)

A complete example showing how to use the framework for a specific application.

## Quick Start: Creating a New Docker Appliance

### Step 1: Copy the Generic Framework

```bash
# Copy the generic appliance
cp -r appliances/docker-generic appliances/your-app-name

# Copy the packer configuration
cp -r apps-code/community-apps/packer/docker-generic apps-code/community-apps/packer/your-app-name
```

### Step 2: Customize the Appliance

Edit `appliances/your-app-name/appliance.sh`:

```bash
# Set your Docker image
ONEAPP_DOCKER_IMAGE="your-docker-image"
ONEAPP_DOCKER_TAG="latest"

# Set default port mappings
ONEAPP_DOCKER_PORTS="${ONEAPP_YOUR_APP_PORTS:-8080:8080}"

# Customize appliance metadata
ONE_SERVICE_NAME='Your App Service - KVM'
ONE_SERVICE_SHORT_DESCRIPTION='Your app description'
```

### Step 3: Update Configuration Files

1. **Update metadata.yaml**:
   ```yaml
   :app:
     :name: your-app-name
     :context:
       :params:
         :YOUR_APP_PORTS: '8080:8080'
         :YOUR_APP_VOLUMES: ''
         # Add your specific parameters
   ```

2. **Update Packer files**:
   - Rename `docker-generic.pkr.hcl` to `your-app-name.pkr.hcl`
   - Update `variables.pkr.hcl` with your appliance name
   - Update all references from "docker-generic" to "your-app-name"

### Step 4: Add to Build System

Edit `apps-code/community-apps/Makefile.config`:

```makefile
SERVICES := lithops lithops_worker rabbitmq ueransim example phoenixrtos srsran openfgs your-app-name
```

### Step 5: Build and Test

```bash
# Build the appliance
cd apps-code/community-apps
make your-app-name

# The built image will be in export/your-app-name.qcow2
```

## Configuration Parameters

The framework supports the following context parameters (all prefixed with `ONEAPP_`):

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `DOCKER_IMAGE` | Docker image name | `nginx` | `pablodelarco/phoenix-rtos-one` |
| `DOCKER_TAG` | Image tag | `latest` | `v1.0.0` |
| `DOCKER_PORTS` | Port mappings | `80:80` | `8080:8080,9090:9090` |
| `DOCKER_VOLUMES` | Volume mappings | - | `/host/data:/app/data` |
| `DOCKER_ENV_VARS` | Environment variables | - | `ENV1=value1,ENV2=value2` |
| `DOCKER_COMMAND` | Custom command | - | `/bin/bash -c "custom command"` |
| `DOCKER_RESTART_POLICY` | Restart policy | `unless-stopped` | `always`, `no`, `on-failure` |
| `DOCKER_NETWORK` | Network mode | `bridge` | `host`, `none` |
| `DOCKER_PRIVILEGED` | Privileged mode | `no` | `yes` |
| `DOCKER_PULL_POLICY` | Image pull policy | `missing` | `always`, `never` |

## Phoenix RTOS Example

The Phoenix RTOS appliance demonstrates how to use the framework:

```bash
# Phoenix RTOS specific parameters
ONEAPP_DOCKER_IMAGE="pablodelarco/phoenix-rtos-one"
ONEAPP_DOCKER_TAG="latest"
ONEAPP_DOCKER_PORTS="${ONEAPP_PHOENIXRTOS_PORTS:-8080:8080}"

# Context parameters for users
ONE_SERVICE_PARAMS=(
    'ONEAPP_PHOENIXRTOS_PORTS'      'configure' 'Port mappings for Phoenix RTOS'    'O|text'
    'ONEAPP_PHOENIXRTOS_VOLUMES'    'configure' 'Volume mappings'                   'O|text'
    'ONEAPP_PHOENIXRTOS_ENV_VARS'   'configure' 'Environment variables'             'O|text'
    # ... more parameters
)
```

## Advanced Customization

### Custom Container Logic

Override the `create_docker_container()` function for application-specific logic:

```bash
create_docker_container()
{
    # Your custom container creation logic
    local container_name="your-app-container"
    
    # Pre-container setup
    setup_application_directories
    
    # Call the generic container creation or implement your own
    # ... custom Docker run command
}
```

### Application-Specific Installation

Override the `service_install()` function to add application-specific setup:

```bash
service_install()
{
    # Call generic Docker installation
    install_docker
    
    # Add your application-specific installation steps
    install_application_dependencies
    configure_application_settings
    
    # Continue with generic setup
    create_one_service_metadata
    postinstall_cleanup
}
```

## Best Practices

1. **Use Ubuntu 22.04 LTS** as the base OS for maximum compatibility
2. **Pre-pull images during build** to reduce startup time
3. **Use meaningful container names** for easier management
4. **Implement proper health checks** in your Docker containers
5. **Document all context parameters** in your appliance documentation
6. **Test with different parameter combinations** before contributing
7. **Follow OpenNebula naming conventions** for consistency

## File Structure

A complete Docker appliance should have this structure:

```
appliances/your-app-name/
├── appliance.sh          # Main appliance script
├── metadata.yaml         # Testing and deployment metadata
├── README.md            # User documentation
├── CHANGELOG.md         # Version history
├── UUID.yaml           # Marketplace metadata (generated)
└── tests/              # Test files
    └── 00-basic.rb     # Basic functionality tests

apps-code/community-apps/packer/your-app-name/
├── your-app-name.pkr.hcl    # Main Packer configuration
├── variables.pkr.hcl        # Build variables
├── common.pkr.hcl          # Common settings
├── gen_context             # Context generation script
├── 81-configure-ssh.sh     # SSH configuration
└── 82-configure-context.sh # Context configuration

logos/
└── your-app-name.png       # Application logo
```

## Contributing to the Marketplace

1. **Follow the framework structure** described above
2. **Test your appliance thoroughly** using the provided test framework
3. **Document all features and parameters** in README.md
4. **Add appropriate tags** in UUID.yaml for discoverability
5. **Submit a pull request** following the contribution guidelines

## Troubleshooting

### Common Issues

1. **Container fails to start**: Check Docker logs with `docker logs container-name`
2. **Port conflicts**: Ensure ports are not already in use on the host
3. **Permission issues**: Consider using privileged mode for system-level containers
4. **Image pull failures**: Check network connectivity and image availability

### Debugging Commands

```bash
# Check container status
docker ps -a

# View container logs
docker logs container-name

# Access container shell
docker exec -it container-name /bin/bash

# Check Docker daemon status
systemctl status docker

# View appliance logs
tail -f /var/log/one-appliance/service.log
```

## Support and Resources

- **OpenNebula Documentation**: https://docs.opennebula.io/
- **Community Marketplace**: https://github.com/OpenNebula/marketplace-community
- **Docker Documentation**: https://docs.docker.com/
- **Packer Documentation**: https://www.packer.io/docs

This framework provides a solid foundation for creating Docker-based appliances while maintaining consistency with OpenNebula best practices and the Community Marketplace standards.
