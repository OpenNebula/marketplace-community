# Creating OpenNebula Appliances - Automatic Method

**Quick appliance creation using the generator script (5 minutes)**

---

## 📖 Introduction

This guide shows you how to quickly create OpenNebula appliances from Docker containers using an automated generator script. The generator creates all necessary files following the proven Phoenix RTOS/Node-RED structure.

**What you'll create:**
- A VM image (QCOW2 format) with Ubuntu 22.04 + Docker
- Automatic Docker container startup on VM boot
- SSH access with password and key authentication
- Console and serial console auto-login
- OpenNebula context integration for runtime configuration

**Time required:** ~5 minutes for generation + 15-20 minutes for building

---

## ✅ Prerequisites

- Linux system (Ubuntu 22.04+ recommended)
- Git
- Packer (for building the image)
- QEMU/KVM (for building the image)

```bash
sudo apt update
sudo apt install -y git qemu-kvm qemu-utils
```

---

## 🚀 Quick Start

### Step 1: Clone Repository

```bash
git clone https://github.com/OpenNebula/marketplace-community.git
cd marketplace-community
```

### Step 2: Create Configuration File

Create a `.env` file with your Docker container details:

```bash
cd docs/automatic-appliance-tutorial

cat > myapp.env << 'ENVEOF'
# Required variables
DOCKER_IMAGE="your-docker-image:tag"
APPLIANCE_NAME="myapp"
APP_NAME="MyApp"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your.email@example.com"

# Optional variables
APP_DESCRIPTION="MyApp description"
APP_FEATURES="Feature 1,Feature 2,Feature 3"
DEFAULT_CONTAINER_NAME="myapp-container"
DEFAULT_PORTS="8080:8080"
DEFAULT_ENV_VARS=""
DEFAULT_VOLUMES="/data:/data"
APP_PORT="8080"
WEB_INTERFACE="true"
ENVEOF
```

### Step 3: Run Generator

```bash
./generate-docker-appliance.sh myapp.env
```

The generator will:
1. Create all appliance files
2. Generate Packer configuration
3. Prompt you to build the image immediately

**Output:**
```
🚀 Loading configuration from myapp.env
🎯 Generating complete appliance: myapp (MyApp)
📁 Creating directory structure...
✅ Directory structure created
📝 Generating metadata.yaml...
✅ Metadata files generated
📝 Generating README.md...
✅ README.md generated
📝 Generating appliance.sh installation script...
✅ appliance.sh generated
📝 Generating Packer configuration files...
✅ Packer configuration files generated
🎉 Appliance 'myapp' generated successfully!

Do you want to build the image now? (y/n):
```

### Step 4: Build the Image

**Note:** The generator automatically registers your appliance in `Makefile.config` by adding it to the SERVICES list. This allows the build system to recognize your appliance.

If you answered 'y' to the generator prompt, the build starts automatically. Otherwise:

```bash
cd ../../apps-code/community-apps
make myapp
```

**Build time:** 15-20 minutes (downloads Ubuntu, installs Docker, pulls your container image)

**Output file:** `export/myapp.qcow2`

---

## 📋 Configuration Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `DOCKER_IMAGE` | Yes | Docker image name | `nginx:alpine` |
| `APPLIANCE_NAME` | Yes | Lowercase name (no spaces) | `nginx` |
| `APP_NAME` | Yes | Display name | `NGINX Web Server` |
| `PUBLISHER_NAME` | Yes | Your name | `John Doe` |
| `PUBLISHER_EMAIL` | Yes | Your email | `john@example.com` |
| `APP_DESCRIPTION` | No | Full description | `NGINX is a web server...` |
| `APP_FEATURES` | No | Comma-separated features | `Web Server,Reverse Proxy` |
| `DEFAULT_CONTAINER_NAME` | No | Container name | `nginx-container` |
| `DEFAULT_PORTS` | No | Port mappings | `80:80,443:443` |
| `DEFAULT_ENV_VARS` | No | Environment variables | `KEY=value,KEY2=value2` |
| `DEFAULT_VOLUMES` | No | Volume mappings | `/data:/data,/config:/config` |
| `APP_PORT` | No | Main application port | `80` |
| `WEB_INTERFACE` | No | Has web UI? | `true` or `false` |

---

## 📁 Generated Files

The generator creates:

```
marketplace-community/
├── appliances/myapp/
│   ├── appliance.sh          # Installation script
│   ├── metadata.yaml         # Build configuration
│   ├── <uuid>.yaml          # Marketplace metadata
│   ├── README.md            # Documentation
│   ├── CHANGELOG.md         # Version history
│   └── tests/
│       └── tests.yaml       # Test configuration
└── apps-code/community-apps/packer/myapp/
    ├── myapp.pkr.hcl        # Packer build file
    └── myapp.auto.pkrvars.hcl  # Packer variables
```

---

## 🔧 Customization

After generation, you can customize the files:

### Modify Container Configuration

Edit `appliances/myapp/appliance.sh`:

```bash
# Change default values
DEFAULT_CONTAINER_NAME="custom-name"
DEFAULT_PORTS="8080:8080,8443:8443"
DEFAULT_ENV_VARS="DEBUG=true,LOG_LEVEL=info"
```

### Add Custom Installation Steps

Add to the `service_install()` function in `appliance.sh`:

```bash
service_install()
{
    # ... existing Docker installation ...
    
    # Add your custom steps here
    apt-get install -y additional-package
    
    # Custom configuration
    echo "custom config" > /etc/myapp.conf
}
```

### Rebuild After Changes

```bash
cd apps-code/community-apps
make clean
make myapp
```

---

## 📦 Examples

See `docs/automatic-appliance-tutorial/examples/` for complete working examples:

### NGINX Web Server

```bash
cat > nginx.env << 'EOF'
DOCKER_IMAGE="nginx:alpine"
APPLIANCE_NAME="nginx"
APP_NAME="NGINX"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="80:80,443:443"
APP_PORT="80"
WEB_INTERFACE="true"
EOF

./generate-docker-appliance.sh nginx.env
```

### Node-RED

```bash
cat > nodered.env << 'EOF'
DOCKER_IMAGE="nodered/node-red:latest"
APPLIANCE_NAME="nodered"
APP_NAME="Node-RED"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="1880:1880"
DEFAULT_VOLUMES="/data:/data"
APP_PORT="1880"
WEB_INTERFACE="true"
EOF

./generate-docker-appliance.sh nodered.env
```

### PostgreSQL Database

```bash
cat > postgres.env << 'EOF'
DOCKER_IMAGE="postgres:16-alpine"
APPLIANCE_NAME="postgres"
APP_NAME="PostgreSQL"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="5432:5432"
DEFAULT_ENV_VARS="POSTGRES_PASSWORD=changeme"
DEFAULT_VOLUMES="/var/lib/postgresql/data:/var/lib/postgresql/data"
APP_PORT="5432"
WEB_INTERFACE="false"
EOF

./generate-docker-appliance.sh postgres.env
```

---

## 🧪 Testing Your Appliance

### 1. Test Locally with QEMU

```bash
cd apps-code/community-apps/export

# Start VM with QEMU
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -smp 2 \
  -drive file=myapp.qcow2,format=qcow2 \
  -net nic -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080 \
  -vnc :0
```

Connect via VNC to `localhost:5900` and verify:
- Console auto-login works
- Docker container is running: `docker ps`
- Application is accessible

### 2. Test on OpenNebula

See the [Manual Appliance Guide](MANUAL_APPLIANCE_GUIDE.md#deploying-to-opennebula) for detailed deployment instructions.

---

## 🐛 Troubleshooting

### Generator Fails

**Problem:** Missing required variables  
**Solution:** Check all required variables are set in .env file

```bash
# Verify your .env file has all required fields
grep -E "DOCKER_IMAGE|APPLIANCE_NAME|APP_NAME|PUBLISHER" myapp.env
```

### Build Fails

**Problem:** Packer build fails  
**Solution:** Check Packer logs

```bash
cd apps-code/community-apps
make myapp 2>&1 | tee build.log
```

Common issues:
- Network connectivity (can't download Ubuntu ISO)
- Insufficient disk space
- Docker image doesn't exist or is private

### Container Doesn't Start

**Problem:** Container fails to start on VM boot  
**Solution:** Check the generated `appliance.sh` for correct Docker image name

```bash
# Verify Docker image name in appliance.sh
grep "DOCKER_IMAGE=" appliances/myapp/appliance.sh
```

### Permission Issues

**Problem:** Container can't write to volumes  
**Solution:** The generator automatically sets ownership to `1000:1000`. If your container uses a different UID, edit `appliance.sh`:

```bash
# In service_install() function
mkdir -p /data
chown 1001:1001 /data  # Change to your container's UID:GID
```

---

## 📤 Next Steps

After successfully building and testing your appliance:

1. **Add a logo** - Create a 256x256 PNG logo at `logos/myapp.png`
2. **Test thoroughly** - Deploy on OpenNebula and verify all functionality
3. **Submit to marketplace** - See [Manual Appliance Guide](MANUAL_APPLIANCE_GUIDE.md#submitting-to-marketplace) for PR instructions

---

## 💡 Tips

- **Start simple** - Begin with minimal configuration, add features incrementally
- **Use official images** - Prefer official Docker images from Docker Hub
- **Test the Docker image first** - Run `docker run` locally before generating appliance
- **Check examples** - Study the example .env files for reference
- **Volume permissions** - If container runs as non-root, ensure volume directories have correct ownership
- **Environment variables** - Use DEFAULT_ENV_VARS for container configuration
- **Port conflicts** - Ensure ports don't conflict with system services

---

## 📖 Additional Resources

- [Manual Appliance Guide](MANUAL_APPLIANCE_GUIDE.md) - For advanced customization
- [OpenNebula Documentation](https://docs.opennebula.io/)
- [Docker Hub](https://hub.docker.com/)
- [Packer Documentation](https://www.packer.io/docs)
- [OpenNebula Marketplace](https://marketplace.opennebula.io/)

