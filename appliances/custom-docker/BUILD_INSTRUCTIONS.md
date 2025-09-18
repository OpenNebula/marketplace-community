# Custom Docker Appliance - Build Instructions

This document provides instructions for building and testing the Custom Docker appliance.

## Overview

The Custom Docker appliance provides Ubuntu 22.04 LTS with Docker pre-installed and configured. It follows the patterns established by the lithops and harbor appliances in the OpenNebula Community Marketplace.

## Prerequisites

1. **OpenNebula Environment**: A working OpenNebula installation with:
   - minione, one-deploy, or manual installation
   - Nested virtualization enabled
   - Internet connectivity for package downloads

2. **Required Packages**: 
   - ansible-core
   - packer (version 1.10.0+)
   - qemu-utils
   - make
   - ruby with rspec gem

3. **Resources**:
   - At least 4GB RAM for building
   - 20GB free disk space
   - 2+ CPU cores recommended

## Building the Appliance

### Step 1: Build Base Ubuntu Image

First, build the Ubuntu 22.04 base image:

```bash
cd marketplace-community/apps-code/one-apps/
sudo make ubuntu2204
```

This will create `export/ubuntu2204.qcow2` which serves as the base for our appliance.

### Step 2: Build Custom Docker Appliance

Build the custom Docker appliance:

```bash
cd marketplace-community/apps-code/community-apps/
sudo make custom-docker
```

If you have `secure_path` enabled in sudo settings:

```bash
sudo env PATH=$PATH make custom-docker
```

### Step 3: Verify Build

Check that the appliance image was created successfully:

```bash
ls -la export/custom-docker.qcow2
```

The image should be approximately 8GB in size.

## Testing the Appliance

### Local Testing Setup

1. **Copy Image to OpenNebula Frontend**:
   ```bash
   cp export/custom-docker.qcow2 /var/tmp/
   ```

2. **Create OpenNebula Image**:
   ```bash
   oneimage create -d <datastore_id> --name "CustomDocker" --type OS --prefix vd --format qcow2 --path /var/tmp/custom-docker.qcow2
   ```

3. **Create VM Template**:
   ```bash
   cat > custom-docker.tmpl <<EOF
   NAME="custom-docker-test"
   CONTEXT=[
     NETWORK="YES",
     ONEAPP_DOCKER_REGISTRY_URL="$ONEAPP_DOCKER_REGISTRY_URL",
     ONEAPP_DOCKER_REGISTRY_USER="$ONEAPP_DOCKER_REGISTRY_USER",
     ONEAPP_DOCKER_REGISTRY_PASSWORD="$ONEAPP_DOCKER_REGISTRY_PASSWORD",
     ONEAPP_ENABLE_DOCKER_BUILDX="$ONEAPP_ENABLE_DOCKER_BUILDX",
     SSH_PUBLIC_KEY="$USER[SSH_PUBLIC_KEY]"
   ]
   CPU="1"
   DISK=[
     IMAGE="CustomDocker",
     IMAGE_UNAME="oneadmin"
   ]
   MEMORY="2048"
   NIC=[
     NETWORK="service"
   ]
   USER_INPUTS=[
     ONEAPP_DOCKER_REGISTRY_URL="O|text|Docker registry URL| |",
     ONEAPP_DOCKER_REGISTRY_USER="O|text|Docker registry username| |",
     ONEAPP_DOCKER_REGISTRY_PASSWORD="O|password|Docker registry password| |",
     ONEAPP_ENABLE_DOCKER_BUILDX="O|boolean|Enable Docker Buildx| |yes"
   ]
   EOF
   
   onetemplate create custom-docker.tmpl
   ```

### Automated Testing

Run the automated tests:

```bash
cd marketplace-community/lib/community/
./app_readiness.rb custom-docker custom-docker.qcow2
```

Expected test results:
- ✓ docker is installed
- ✓ docker compose is available  
- ✓ docker service is running
- ✓ docker can run containers
- ✓ docker daemon configuration is applied
- ✓ docker version is correct
- ✓ docker buildx is available
- ✓ check oneapps motd
- ✓ docker info shows correct configuration
- ✓ docker service is enabled
- ✓ docker can pull and list images
- ✓ docker system shows healthy status

### Manual Testing

1. **Instantiate VM**:
   ```bash
   onetemplate instantiate <template_id>
   ```

2. **SSH into VM**:
   ```bash
   ssh root@<vm_ip>
   ```

3. **Verify Docker Installation**:
   ```bash
   docker --version
   docker info
   docker run hello-world
   docker compose version
   ```

4. **Test Docker Functionality**:
   ```bash
   # Pull and run a container
   docker run -d --name nginx-test nginx:alpine
   docker ps
   docker logs nginx-test
   docker stop nginx-test
   docker rm nginx-test
   ```

## Troubleshooting

### Build Issues

1. **Packer fails to start VM**:
   - Check nested virtualization is enabled
   - Verify KVM acceleration is available
   - Ensure sufficient resources

2. **Docker installation fails**:
   - Check internet connectivity
   - Verify Ubuntu repositories are accessible
   - Review appliance.sh logs

3. **Context configuration fails**:
   - Check SSH configuration
   - Verify one-context packages are installed

### Test Issues

1. **Tests timeout**:
   - Increase timeout values in test files
   - Check VM has sufficient resources
   - Verify network connectivity

2. **Docker service not starting**:
   - Check systemd logs: `journalctl -u docker`
   - Verify Docker daemon configuration
   - Check disk space availability

## File Structure Summary

```
marketplace-community/
├── appliances/custom-docker/
│   ├── appliance.sh                    # Main appliance script
│   ├── metadata.yaml                   # Testing metadata
│   ├── a5550f73-...-3146.yaml         # Marketplace metadata
│   ├── README.md                       # User documentation
│   ├── CHANGELOG.md                    # Version history
│   ├── tests.yaml                      # Test file list
│   └── tests/
│       └── 00-custom_docker_basic.rb   # Test suite
├── apps-code/community-apps/
│   ├── Makefile.config                 # Updated with custom-docker
│   └── packer/custom-docker/
│       ├── custom-docker.pkr.hcl       # Main Packer config
│       ├── variables.pkr.hcl           # Packer variables
│       ├── common.pkr.hcl              # Common settings
│       ├── gen_context                 # Context generator
│       ├── 81-configure-ssh.sh         # SSH configuration
│       └── 82-configure-context.sh     # Context configuration
└── logos/
    └── custom-docker.png.placeholder   # Logo placeholder
```

## Next Steps

1. **Create actual logo**: Replace the placeholder with a proper PNG logo
2. **Test thoroughly**: Run comprehensive tests in your environment
3. **Customize as needed**: Modify context parameters or Docker configuration
4. **Submit to marketplace**: Follow the contribution process when ready

## Support

For issues or questions:
- Check OpenNebula documentation
- Review existing appliance examples (lithops, harbor)
- Consult the Docker Appliance Framework documentation
- Use OpenNebula community forums
