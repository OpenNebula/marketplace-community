# 🚀 Docker Appliance Generator for OpenNebula

**Turn any Docker container into a complete OpenNebula appliance in minutes!**

## ⚡ Quick Start

```bash
# 1. Create config file
nano myapp.env

# 2. Generate complete appliance
./generate-docker-appliance.sh myapp.env

# 3. Build VM image (optional)
cd ../apps-code/community-apps
make myapp
```

**Result**: Complete OpenNebula appliance with 13+ files generated automatically!

## 📚 Complete Guide

**👉 See [QUICK_START_GUIDE.md](../QUICK_START_GUIDE.md) for the complete step-by-step tutorial**

The guide covers:
- ✅ **Setup** - Clone repository and prepare environment
- ✅ **Configuration** - Create your Docker container config
- ✅ **Generation** - Run the generator to create all files
- ✅ **Building** - Build the actual VM image (optional)
- ✅ **Testing** - Verify your appliance works
- ✅ **Sharing** - Submit to OpenNebula marketplace
- ✅ **Examples** - Real configurations for popular containers
- ✅ **Troubleshooting** - Solutions for common issues

## 🎯 What Gets Generated

**13+ files created automatically**:
- ✅ **appliance.sh** - Complete Docker installation with your container config
- ✅ **metadata.yaml** - Build configuration
- ✅ **README.md** - Documentation with your app details
- ✅ **Packer files** - VM build configuration
- ✅ **Test files** - Automated testing framework
- ✅ **Context files** - OpenNebula integration

## 🌟 Features

- 🐳 **Any Docker container** - Works with any image from Docker Hub
- ⚡ **2-minute setup** - Just set variables and run
- 🤖 **Complete automation** - All files generated with your config
- 🖥️ **VNC + SSH access** - Desktop and terminal access included
- 🔧 **OpenNebula integration** - Context variables, key auth, monitoring
- 📦 **Ready to build** - Complete VM image in 15-30 minutes

## 📝 Example Config

```bash
# myapp.env
DOCKER_IMAGE="nginx:alpine"
APPLIANCE_NAME="nginx"
APP_NAME="NGINX Web Server"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your.email@domain.com"
APP_DESCRIPTION="High-performance web server"
APP_FEATURES="Web server,Reverse proxy,Load balancing"
DEFAULT_PORTS="80:80,443:443"
DEFAULT_VOLUMES="/var/www/html:/usr/share/nginx/html"
WEB_INTERFACE="true"
```

## 🚀 Ready to Start?

**👉 Follow the complete guide: [QUICK_START_GUIDE.md](../QUICK_START_GUIDE.md)**

**Time needed**: 15-30 minutes total
**Result**: Production-ready OpenNebula appliance
**Skill level**: Beginner-friendly (no OpenNebula experience required)

## 🧪 Full Test (After Building)
If you built the VM image, test it in OpenNebula:

### 1. Copy Image to OpenNebula Frontend
```bash
# Copy the built qcow2 image to OpenNebula frontend
scp apps-code/community-apps/export/your-appliance.qcow2 root@opennebula-frontend:/var/tmp/
```

### 2. Create OpenNebula Image
```bash
# SSH to OpenNebula frontend
ssh root@opennebula-frontend

# Create image in OpenNebula (replace with your datastore ID)
oneimage create --name "your-appliance" --path "/var/tmp/your-appliance.qcow2" --driver qcow2 --datastore 1
```

### 3. Create VM Template
```bash
# Create VM template with proper context configuration
cat > your-appliance-template.txt << 'EOF'
NAME = "your-appliance-template"
CPU = "2"
MEMORY = "2048"
DISK = [
  IMAGE_ID = "IMAGE_ID_FROM_STEP_2"
]
NIC = [
  NETWORK_ID = "0"
]
CONTEXT = [
  NETWORK = "YES",
  SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]",
  SET_HOSTNAME = "$USER[SET_HOSTNAME]"
]
GRAPHICS = [
  TYPE = "VNC",
  LISTEN = "0.0.0.0"
]
EOF

# Create the template
onetemplate create your-appliance-template.txt
```

### 4. Deploy and Test VM
```bash
# Instantiate VM from template
onetemplate instantiate TEMPLATE_ID --name "test-appliance-vm"

# Wait for VM to be running
onevm show VM_ID

# Get VM IP address
onevm show VM_ID | grep IP

# Test SSH access (replace VM_IP with actual IP)
ssh root@VM_IP

# Once connected via SSH, verify the appliance:
# 1. Check Docker service is running
systemctl status docker

# 2. Verify container is running
docker ps

# 3. Check container logs
docker logs CONTAINER_NAME

# 4. Test application (for web apps)
curl http://localhost:PORT
# Or visit http://VM_IP:PORT in browser

# 5. Test console access via OpenNebula (should auto-login as root)
# Use OpenNebula Sunstone console or VNC viewer
```

### 5. Verify OpenNebula Context Integration
```bash
# Check context variables were applied
cat /var/lib/one-context/context.sh

# Verify SSH keys were installed
cat ~/.ssh/authorized_keys

# Check hostname was set
hostname

# Verify network configuration
ip addr show
```

### Example: Testing Node-RED Appliance
```bash
# After VM is running and you have the IP:
ssh root@VM_IP

# Check Node-RED container
docker ps
# Should show: nodered/node-red:latest container running

# Check Node-RED logs
docker logs nodered-app

# Test Node-RED web interface
curl http://localhost:1880
# Or visit http://VM_IP:1880 in browser

# Verify welcome message
cat /etc/profile.d/99-nodered-welcome.sh
```

### Troubleshooting
- **SSH fails**: Recreate VM template (OpenNebula context resolution issue)
- **Container not running**: Check `docker logs` and `systemctl status docker`
- **Web interface not accessible**: Verify container port mapping and firewall
- **Console access**: Use OpenNebula Sunstone VNC console with auto-login
