# Docker Appliance Creation Checklist

Quick reference checklist for creating OpenNebula marketplace appliances from Docker containers.

## Pre-Development Checklist

- [ ] **Docker image identified**: What container will you use?
- [ ] **Appliance name chosen**: Single lowercase word (e.g., `nginx`, `postgres`, `redis`)
- [ ] **Ports identified**: What ports need to be exposed?
- [ ] **Volumes planned**: What data needs to persist?
- [ ] **Environment variables**: What configuration is needed?
- [ ] **Logo prepared**: PNG format for `logos/YOURAPP.png`

## File Creation Checklist

### Core Files
- [ ] `appliances/YOURAPP/metadata.yaml` - Build configuration
- [ ] `appliances/YOURAPP/UUID.yaml` - Main appliance metadata  
- [ ] `appliances/YOURAPP/appliance.sh` - Installation script
- [ ] `appliances/YOURAPP/README.md` - Documentation
- [ ] `appliances/YOURAPP/CHANGELOG.md` - Version history

### Packer Files
- [ ] `apps-code/community-apps/packer/YOURAPP/YOURAPP.pkr.hcl` - Main Packer config
- [ ] `apps-code/community-apps/packer/YOURAPP/variables.pkr.hcl` - Packer variables
- [ ] `apps-code/community-apps/packer/YOURAPP/postprocess.sh` - Post-processing
- [ ] `apps-code/community-apps/packer/YOURAPP/gen_context` - Context generator
- [ ] `apps-code/community-apps/packer/YOURAPP/82-configure-context.sh` - Context config

### Test Files
- [ ] `appliances/YOURAPP/tests.yaml` - Test file list
- [ ] `appliances/YOURAPP/tests/00-YOURAPP_basic.rb` - Test script
- [ ] `appliances/YOURAPP/context.yaml` - Test configuration

## Customization Checklist

### appliance.sh Customizations
- [ ] **DOCKER_IMAGE**: Set to your container image
- [ ] **DEFAULT_CONTAINER_NAME**: Set container name
- [ ] **DEFAULT_PORTS**: Configure port mappings (host:container)
- [ ] **DEFAULT_ENV_VARS**: Set environment variables (VAR1=value1,VAR2=value2)
- [ ] **DEFAULT_VOLUMES**: Configure volume mounts (/host:/container)
- [ ] **APP_NAME**: Set your application display name
- [ ] **APP_PORT**: Set main application port
- [ ] **WEB_INTERFACE**: Set to "true" or "false"

### Packer Customizations
- [ ] **YOURAPP.pkr.hcl**: Replace "YOURAPP" with your app name
- [ ] **variables.pkr.hcl**: Update appliance_name default value
- [ ] **gen_context**: Update SET_HOSTNAME default
- [ ] **postprocess.sh**: Update service names and descriptions

### Documentation Customizations
- [ ] **README.md**: Replace placeholders with your app info
- [ ] **CHANGELOG.md**: Update with your app details and version
- [ ] **UUID.yaml**: Complete all metadata fields
- [ ] **metadata.yaml**: Add logo path and user inputs

### Test Customizations
- [ ] **00-YOURAPP_basic.rb**: Replace YOURAPP and CONTAINER_NAME
- [ ] **Add app-specific health checks**: Customize the "responsive" test
- [ ] **context.yaml**: Update image name and timeouts

## Build and Test Checklist

### Pre-Build
- [ ] **All files created** and customized
- [ ] **YAML files validated** with yamllint
- [ ] **Scripts have execute permissions**
- [ ] **Logo file exists** in correct location

### Build Process
- [ ] **Navigate to apps-code directory**: `cd marketplace-community/apps-code`
- [ ] **Run build command**: `make YOURAPP`
- [ ] **Build completes successfully**
- [ ] **Image file created**: `appliances/YOURAPP/YOURAPP.qcow2`

### Testing
- [ ] **Run test suite**: Tests pass without errors
- [ ] **Manual VM deployment**: VM boots successfully
- [ ] **VNC access**: Can connect via VNC
- [ ] **SSH access**: Can connect with OpenNebula context keys
- [ ] **Docker service**: Running and enabled
- [ ] **Container startup**: Container starts automatically
- [ ] **Port accessibility**: Can access configured ports
- [ ] **Volume persistence**: Data persists in configured volumes
- [ ] **Environment variables**: Container respects env vars
- [ ] **Web interface**: Accessible if applicable
- [ ] **Container logs**: No critical errors

## Submission Checklist

### Pre-Submission
- [ ] **Thorough testing completed** on OpenNebula 7.0+
- [ ] **All tests pass** consistently
- [ ] **Documentation reviewed** for accuracy
- [ ] **Logo added** to repository
- [ ] **Naming convention followed**: Single lowercase word

### Git Workflow
- [ ] **Repository forked** from OpenNebula/marketplace-community
- [ ] **Clean branch created**: `YOURAPP-appliance`
- [ ] **All changes committed** with descriptive messages
- [ ] **Branch pushed** to your fork

### Pull Request
- [ ] **PR created** from your fork to OpenNebula/marketplace-community
- [ ] **PR template used** with complete information
- [ ] **Appliance name specified**: `:app: YOURAPP`
- [ ] **Type marked**: "New Appliance" checked
- [ ] **Description complete**: Features and technical details included
- [ ] **Contributor checklist**: All items checked

## Common Customization Examples

### Web Application (like NGINX)
```bash
DOCKER_IMAGE="nginx:alpine"
DEFAULT_PORTS="80:80,443:443"
WEB_INTERFACE="true"
```

### Database (like PostgreSQL)
```bash
DOCKER_IMAGE="postgres:15"
DEFAULT_PORTS="5432:5432"
DEFAULT_ENV_VARS="POSTGRES_PASSWORD=opennebula"
WEB_INTERFACE="false"
```

### Cache/Queue (like Redis)
```bash
DOCKER_IMAGE="redis:alpine"
DEFAULT_PORTS="6379:6379"
DEFAULT_VOLUMES="/data:/data"
WEB_INTERFACE="false"
```

## Quick Commands Reference

```bash
# Create directory structure
mkdir -p appliances/YOURAPP/tests
mkdir -p apps-code/community-apps/packer/YOURAPP

# Build appliance
cd marketplace-community/apps-code
make YOURAPP

# Run tests
cd marketplace-community
ruby -I lib appliances/YOURAPP/tests/00-YOURAPP_basic.rb

# Validate YAML
yamllint appliances/YOURAPP/*.yaml
```

## Troubleshooting Quick Fixes

- **Build fails**: Check ISO URL/checksum in variables.pkr.hcl
- **Container won't start**: Verify Docker image name and availability
- **Tests timeout**: Increase timeout values in context.yaml
- **SSH fails**: Check OpenNebula context key injection
- **Ports not accessible**: Verify port mappings and firewall

---

**📖 For detailed instructions, see [DOCKER_APPLIANCE_GUIDE.md](DOCKER_APPLIANCE_GUIDE.md)**
