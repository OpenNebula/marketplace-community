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
git checkout dcos/add-appliance-automation-script
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

If you answered 'y' to the prompt, the build starts automatically. Otherwise:

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

**Important:** After modifying `appliance.sh` or any other appliance files, you **must rebuild** the image for changes to take effect. The scripts are executed during the Packer build process and are embedded into the final image.

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

### Nextcloud All-in-One

```bash
cat > nextcloud.env << 'EOF'
DOCKER_IMAGE="nextcloud/all-in-one:latest"
APPLIANCE_NAME="nextcloud"
APP_NAME="Nextcloud"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="80:80,8080:8080,8443:8443"
DEFAULT_VOLUMES="/var/run/docker.sock:/var/run/docker.sock:ro,nextcloud_aio_mastercontainer:/mnt/docker-aio-config"
APP_PORT="8080"
WEB_INTERFACE="true"
EOF

./generate-docker-appliance.sh nextcloud.env
```

**Note**: Nextcloud All-in-One requires access to the Docker socket for managing additional containers. Access the web interface at `http://VM_IP:8080` to complete the setup.

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

#### Step 2.1: Create OpenNebula Image

Copy the built image to a location accessible by OpenNebula:

```bash
# Copy the image to a temporary location
cp export/myapp.qcow2 /var/tmp/

# Create the image in OpenNebula
oneimage create --name "MyApp" \
  --description "MyApp appliance created with automatic method" \
  --type OS \
  --datastore 1 \
  --path /var/tmp/myapp.qcow2
```

**Note:** Replace `myapp` with your appliance name. The command will output an IMAGE_ID (e.g., `ID: 4`). Save this ID for the next step.

#### Step 2.2: Create VM Template

Create a VM template that uses your image:

```bash
cat > myapp-template.txt << 'EOF'
NAME = "myapp-template"
CPU = "2"
MEMORY = "2048"
DISK = [
  IMAGE_ID = "X"
]
NIC = [
  NETWORK_ID = "0"
]
CONTEXT = [
  NETWORK = "YES",
  SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]",
  SET_HOSTNAME = "$NAME"
]
GRAPHICS = [
  TYPE = "VNC",
  LISTEN = "0.0.0.0"
]
EOF

# Create the template
onetemplate create myapp-template.txt
```

**Note:** The command will output a TEMPLATE_ID (e.g., `ID: 5`). Save this ID for the next step.

#### Step 2.3: Instantiate the VM

```bash
# Replace <TEMPLATE_ID> with the ID from step 2.2
onetemplate instantiate <TEMPLATE_ID> --name "myapp-test"
```

Wait for the VM to reach the RUNNING state:

```bash
# Check VM status
onevm list

# Get detailed VM information including IP address
onevm show <VM_ID>

# SSH to the VM (if OpenNebula is on your local machine)
onevm ssh <VM_ID>
```

#### Step 2.4: Access the Application

Once the VM is running, you can access it via SSH and the web interface (if applicable).

**SSH Access:**

```bash
# If OpenNebula is on a remote host, use SSH port forwarding
# Replace:
#   - 8080 with your application's port (from APP_PORT in .env)
#   - 172.16.100.X with your VM's IP address
#   - user@opennebula-host with your OpenNebula frontend credentials

ssh -L 8080:172.16.100.X:8080 user@opennebula-host
```

**Web Interface Access:**

If your application has a web interface (`WEB_INTERFACE="true"`), open your browser:

```
http://localhost:8080
```

**Direct SSH to VM:**

```bash
# From the OpenNebula host
ssh root@172.16.100.X

# Verify the container is running
docker ps

# Check container logs
docker logs <container-name>
```

#### Verification Checklist

- ✅ VM boots successfully
- ✅ Network configuration is applied (check with `ip addr`)
- ✅ Docker service is running (`systemctl status docker`)
- ✅ Container is running (`docker ps`)
- ✅ Application is accessible via web interface (if applicable)
- ✅ SSH access works with password and key authentication
- ✅ Console auto-login works (check via VNC)

---

## 📤 Next Steps

### 1. Add a Logo

Create a 256x256 PNG logo for your appliance to display in the OpenNebula Sunstone UI.

#### Step 1: Create or Download the Logo

**Option A: Download from official source**
```bash
# Example: Download Nextcloud logo
wget -O /tmp/app-logo.png "https://raw.githubusercontent.com/nextcloud/promo/master/nextcloud-logo-inverted.png"
```

**Option B: Create your own logo**
- Use any image editor (GIMP, Photoshop, etc.)
- Export as PNG with transparent background

#### Step 2: Resize to 256x256

```bash
# Install ImageMagick if not available
apt-get install imagemagick

# Resize and save to logos directory
convert /tmp/app-logo.png -resize 256x256 -background none -gravity center -extent 256x256 logos/myapp.png

# Verify the logo
ls -lh logos/myapp.png
file logos/myapp.png
```

**Requirements:**
- Format: PNG
- Size: 256x256 pixels
- Transparent background recommended
- Clear, recognizable icon representing your application

#### Step 3: Deploy Logo to OpenNebula

For the logo to appear in Sunstone, copy it to the FireEdge assets directory:

```bash
# Copy logo to FireEdge assets (on OpenNebula frontend)
sudo cp logos/myapp.png /usr/lib/one/fireedge/dist/client/assets/images/logos/

# Verify the file
ls -lh /usr/lib/one/fireedge/dist/client/assets/images/logos/myapp.png

# Restart FireEdge to pick up the new logo
sudo systemctl restart opennebula-fireedge
```

#### Step 4: Update Image and Template

Update your OpenNebula image and template to reference the logo:

```bash
# Create logo attribute file
cat > /tmp/logo-update.txt << 'EOF'
LOGO = "images/logos/myapp.png"
EOF

# Update the image (replace IMAGE_ID with your image ID)
oneimage update IMAGE_ID /tmp/logo-update.txt

# Update the template (replace TEMPLATE_ID with your template ID)
onetemplate update TEMPLATE_ID /tmp/logo-update.txt

# Verify the logo attribute
oneimage show IMAGE_ID | grep LOGO
onetemplate show TEMPLATE_ID | grep LOGO
```

#### Step 5: Verify in Sunstone

1. Open Sunstone web interface
2. Go to **Templates → VM Templates** or **Storage → Images**
3. You should see your logo displayed next to the appliance
4. If not visible, do a hard refresh (Ctrl+Shift+R or Cmd+Shift+R)

**Example for Nextcloud:**
```bash
# Download and prepare logo
wget -O /tmp/nextcloud-logo.png "https://raw.githubusercontent.com/nextcloud/promo/master/nextcloud-logo-inverted.png"
convert /tmp/nextcloud-logo.png -resize 256x256 -background none -gravity center -extent 256x256 logos/nextcloud.png

# Deploy to OpenNebula
sudo cp logos/nextcloud.png /usr/lib/one/fireedge/dist/client/assets/images/logos/
sudo systemctl restart opennebula-fireedge

# Update image and template
cat > /tmp/logo-update.txt << 'EOF'
LOGO = "images/logos/nextcloud.png"
EOF
oneimage update 4 /tmp/logo-update.txt
onetemplate update 3 /tmp/logo-update.txt
```

### 2. Submit to Marketplace

Once your appliance is tested and working, submit it to the OpenNebula Marketplace:

#### Create Fork and Branch

```bash
# Fork the repository on GitHub first (https://github.com/OpenNebula/marketplace-community)
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/marketplace-community.git
cd marketplace-community

# Create feature branch
git checkout -b feature/add-myapp-appliance
```

#### Add Your Files

```bash
git add appliances/myapp/
git add apps-code/community-apps/packer/myapp/
git add logos/myapp.png

git commit -m "Add MyApp appliance

- Docker container with automatic startup
- OpenNebula context integration
- SSH and console access
- Web interface on port 8080"
```

#### Push and Create PR

```bash
git push origin feature/add-myapp-appliance
```

Go to GitHub and create a Pull Request with:

**Title:** `Add MyApp appliance`

**Description:**
```markdown
## Description

This PR adds a new appliance for MyApp, a [brief description].

## Features

- Docker container with automatic startup
- OpenNebula context integration
- Configurable via context variables:
  - Container name
  - Port mappings
  - Environment variables
  - Volume mappings

## Testing

- ✅ Built successfully with Packer
- ✅ Deployed to OpenNebula
- ✅ Container starts automatically
- ✅ SSH access works (password + keys)
- ✅ Console auto-login works
- ✅ Application accessible on configured ports

## Files Added

- `appliances/myapp/` - Appliance definition files
- `apps-code/community-apps/packer/myapp/` - Packer build configuration
- `logos/myapp.png` - Appliance logo

## Checklist

- [x] Appliance builds successfully
- [x] Appliance tested on OpenNebula
- [x] Documentation included (README.md)
- [x] Logo added (256x256 PNG)
- [x] Follows community appliance structure
- [x] No sensitive information in files
```

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

