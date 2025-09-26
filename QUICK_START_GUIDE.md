# 🚀 Complete Guide: Create Your Docker Appliance

**Turn any Docker container into a complete OpenNebula virtual machine appliance in minutes!**

## 🎯 What You'll Create

By following this guide, you'll create a **complete virtual machine appliance** that:
- ✅ Runs your Docker container automatically on VM startup
- ✅ Has desktop access (VNC) and SSH access with key authentication
- ✅ Can be deployed instantly on OpenNebula cloud platforms
- ✅ Is ready for the OpenNebula Community Marketplace
- ✅ Includes all necessary configuration files and build scripts

## 📋 What You Need

### Required:
- 🖥️ **Linux computer** (Ubuntu 20.04+ recommended)
- 🌐 **Internet connection**
- 🐳 **Docker container** you want to use (any from Docker Hub)
- ⏱️ **15-30 minutes** (5 minutes setup + 10-25 minutes building)

### For Building (Optional):
- 🛠️ **Packer** and **QEMU** (we'll install these)
- 💾 **10GB free disk space** (for building VM images)

**No OpenNebula knowledge required!** This guide explains everything step by step.

## 🎓 Quick Overview

### What is an OpenNebula Appliance?
An **appliance** is a ready-to-use virtual machine image containing:
- **Ubuntu 22.04 LTS** operating system
- **Your Docker application** pre-installed and auto-starting
- **VNC desktop access** for GUI interaction
- **SSH access** with key authentication from OpenNebula
- **All dependencies** and configuration pre-configured

### What is OpenNebula?
**OpenNebula** is an open-source cloud platform used by companies and universities worldwide. The **Community Marketplace** is where people share these ready-to-use VM images.

---

## 🛠️ Step 1: Set Up Your Environment

### Download the Repository

Open a terminal and run these commands:

```bash
# Go to your home directory
cd ~

# Clone the OpenNebula marketplace repository
git clone https://github.com/OpenNebula/marketplace-community.git

# Enter the repository
cd marketplace-community/tools

# Verify the generator is ready
ls -la generate-docker-appliance.sh
```

**Expected output**: You should see the generator script with execute permissions (`-rwxr-xr-x`)

If the script isn't executable, run:
```bash
chmod +x generate-docker-appliance.sh
```

---

## ⚙️ Step 2: Configure Your Docker Container

### Choose Your Docker Container

Pick any Docker container from Docker Hub. Popular examples:
- **Web servers**: `nginx:alpine`, `httpd:alpine`, `caddy:alpine`
- **Databases**: `postgres:15`, `mysql:8`, `redis:alpine`
- **Applications**: `wordpress:latest`, `nextcloud:latest`, `gitlab/gitlab-ce:latest`
- **Development**: `node:18`, `python:3.11`, `openjdk:17`

### Create Your Configuration File

Let's create a configuration file using NGINX as an example:

```bash
# Create your configuration file
nano my-nginx-app.env
```

**Copy and paste this template, then customize it for your container**:

```bash
# REQUIRED: Your Docker container image
DOCKER_IMAGE="nginx:alpine"

# REQUIRED: Your appliance name (single lowercase word, no spaces or dashes)
APPLIANCE_NAME="mynginx"

# REQUIRED: Display name for your application
APP_NAME="My NGINX Web Server"

# REQUIRED: Your information (will appear in the marketplace)
PUBLISHER_NAME="John Doe"
PUBLISHER_EMAIL="john.doe@example.com"

# REQUIRED: Describe what your application does
APP_DESCRIPTION="NGINX is a high-performance web server and reverse proxy"

# REQUIRED: List the main features (comma-separated)
APP_FEATURES="High performance web server,Reverse proxy,Load balancing,SSL support"

# OPTIONAL: Container configuration (customize these for your needs)
DEFAULT_CONTAINER_NAME="nginx-server"
DEFAULT_PORTS="80:80,443:443"
DEFAULT_ENV_VARS=""
DEFAULT_VOLUMES="/var/www/html:/usr/share/nginx/html"

# OPTIONAL: Application settings
APP_PORT="80"
WEB_INTERFACE="true"
```

**Save the file** (in nano: Ctrl+X, then Y, then Enter)

### Customize for Your Container

**Important**: Modify these key values for your specific container:

| Field | What to Change | Examples |
|-------|----------------|----------|
| `DOCKER_IMAGE` | Your container image | `"postgres:15"`, `"redis:alpine"`, `"wordpress:latest"` |
| `APPLIANCE_NAME` | Single word, lowercase | `"postgres"`, `"redis"`, `"wordpress"` |
| `APP_NAME` | Display name | `"PostgreSQL Database"`, `"Redis Cache"` |
| `DEFAULT_PORTS` | Ports your app uses | `"5432:5432"` (PostgreSQL), `"6379:6379"` (Redis) |
| `DEFAULT_ENV_VARS` | Environment variables | `"POSTGRES_PASSWORD=secret,POSTGRES_DB=myapp"` |
| `DEFAULT_VOLUMES` | Data directories | `"/data:/var/lib/postgresql/data"` |
| `WEB_INTERFACE` | Has web UI? | `"false"` for databases, `"true"` for web apps |

---

## 🚀 Step 3: Generate Your Appliance

### Run the Generator

```bash
# Generate your complete appliance (replace with your file name)
./generate-docker-appliance.sh my-nginx-app.env
```

**Expected output**:
```
[INFO] 🚀 Loading configuration from my-nginx-app.env
[INFO] 🎯 Generating complete appliance: mynginx (My NGINX Web Server)
[SUCCESS] Directory structure created
[SUCCESS] Metadata files generated
[SUCCESS] README.md generated
[SUCCESS] appliance.sh generated
[SUCCESS] Packer configuration files generated
[SUCCESS] Additional files generated
[INFO] 🎉 Appliance 'mynginx' generated successfully!
```

### Verify Files Were Created

```bash
# Check your appliance files were created
ls -la ../appliances/mynginx/

# You should see:
# - metadata.yaml, README.md, appliance.sh
# - CHANGELOG.md, tests.yaml, context.yaml
# - tests/ directory
```

**🎉 Success!** Your appliance is now generated with ALL necessary files.

---

## 🏗️ Step 4: Build Your Appliance (Optional)

**This step creates the actual VM image file. Skip if you just want to test the generator.**

### Install Build Tools

**Ubuntu/Debian**:
```bash
# Install virtualization tools
sudo apt update
sudo apt install -y qemu-kvm qemu-utils

# Install Packer (HashiCorp's VM builder)
wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
unzip packer_1.9.4_linux_amd64.zip
sudo mv packer /usr/local/bin/

# Verify installation
packer version
```

**CentOS/RHEL**:
```bash
sudo yum install -y qemu-kvm qemu-img
# Then install Packer as above
```

### Add Your Appliance to Build System

```bash
# Go to the build directory
cd ../apps-code/community-apps

# Edit the services list
nano Makefile.config
```

Find the `SERVICES :=` line and add your appliance:
```bash
# Before:
SERVICES := lithops lithops_worker rabbitmq ueransim example phoenixrtos srsran openfgs

# After (add mynginx):
SERVICES := lithops lithops_worker rabbitmq ueransim example phoenixrtos srsran openfgs mynginx
```

Save the file (Ctrl+X, Y, Enter).

### Build the VM Image

```bash
# Build your appliance (takes 15-30 minutes)
make mynginx
```

**What happens during build**:
1. 📥 Downloads Ubuntu 22.04 LTS ISO (~4GB)
2. 🖥️ Creates virtual machine with 2GB RAM, 8GB disk
3. 💿 Installs Ubuntu automatically
4. 🐳 Installs Docker and your container
5. ⚙️ Configures VNC, SSH, and OpenNebula integration
6. 📦 Creates final `.qcow2` image file

**Build time**: 15-30 minutes (depending on internet speed)

### Verify Build Success

```bash
# Check the built image
ls -la export/mynginx.qcow2

# Should show a file ~2-4GB in size
```

**🎉 Success!** Your appliance is now a complete VM image ready for deployment.

---

## 🧪 Step 5: Test Your Appliance (Optional)

### Quick Test (Without Building)

You can test the generated files without building:

```bash
# Check appliance.sh contains your Docker config
grep -A 5 -B 5 "your-docker-image" ../appliances/mynginx/appliance.sh

# Verify context configuration
cat ../appliances/mynginx/context.yaml

# Check documentation
head -20 ../appliances/mynginx/README.md
```

### Full Test (After Building)

If you built the VM image, test it:

1. **Deploy on virtualization platform** (VirtualBox, KVM, etc.)
2. **Boot the VM** and wait for startup
3. **Test VNC access** (should auto-login as root)
4. **Test SSH access** with your OpenNebula keys
5. **Verify container is running**: `docker ps`
6. **Test your application** (e.g., visit http://VM_IP:80 for web apps)

---

## 📤 Step 6: Share Your Appliance

### Submit to OpenNebula Marketplace

1. **Fork the repository** on GitHub:
   - Go to https://github.com/OpenNebula/marketplace-community
   - Click "Fork" button

2. **Create a branch** for your appliance:
   ```bash
   git checkout -b mynginx-appliance
   ```

3. **Add your files**:
   ```bash
   git add ../appliances/mynginx/
   git add ../apps-code/community-apps/packer/mynginx/
   git add Makefile.config  # if you added to SERVICES
   git commit -m "Add My NGINX Web Server appliance"
   git push origin mynginx-appliance
   ```

4. **Create a Pull Request**:
   - Go to your forked repository on GitHub
   - Click "New Pull Request"
   - Fill out the template with your appliance information

---

## 🎯 Real Examples

### Example 1: PostgreSQL Database
```bash
# postgres.env
DOCKER_IMAGE="postgres:15"
APPLIANCE_NAME="postgres"
APP_NAME="PostgreSQL Database"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your.email@domain.com"
APP_DESCRIPTION="PostgreSQL is a powerful open-source database"
APP_FEATURES="ACID compliance,JSON support,Full-text search,Advanced indexing"
DEFAULT_CONTAINER_NAME="postgres-db"
DEFAULT_PORTS="5432:5432"
DEFAULT_ENV_VARS="POSTGRES_PASSWORD=opennebula,POSTGRES_DB=myapp,POSTGRES_USER=postgres"
DEFAULT_VOLUMES="/var/lib/postgresql/data:/var/lib/postgresql/data"
APP_PORT="5432"
WEB_INTERFACE="false"
```

### Example 2: Redis Cache
```bash
# redis.env
DOCKER_IMAGE="redis:alpine"
APPLIANCE_NAME="redis"
APP_NAME="Redis Cache"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your.email@domain.com"
APP_DESCRIPTION="Redis is an in-memory data store and cache"
APP_FEATURES="High performance caching,Data persistence,Pub/Sub messaging"
DEFAULT_CONTAINER_NAME="redis-cache"
DEFAULT_PORTS="6379:6379"
DEFAULT_ENV_VARS=""
DEFAULT_VOLUMES="/data:/data"
APP_PORT="6379"
WEB_INTERFACE="false"
```

### Example 3: WordPress Website
```bash
# wordpress.env
DOCKER_IMAGE="wordpress:latest"
APPLIANCE_NAME="wordpress"
APP_NAME="WordPress Website"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your.email@domain.com"
APP_DESCRIPTION="WordPress is a popular content management system"
APP_FEATURES="Easy website creation,Plugin system,Theme support,SEO friendly"
DEFAULT_CONTAINER_NAME="wordpress-site"
DEFAULT_PORTS="80:80"
DEFAULT_ENV_VARS="WORDPRESS_DB_HOST=localhost,WORDPRESS_DB_NAME=wordpress"
DEFAULT_VOLUMES="/var/www/html:/var/www/html"
APP_PORT="80"
WEB_INTERFACE="true"
```

---

## ❓ Troubleshooting

### Common Issues & Solutions

**❌ "Permission denied" when running script**
```bash
chmod +x generate-docker-appliance.sh
```

**❌ "Command not found: git"**
```bash
# Ubuntu/Debian
sudo apt install git

# CentOS/RHEL
sudo yum install git
```

**❌ "Docker image not found" during build**
- Verify your `DOCKER_IMAGE` name is correct
- Check the image exists on Docker Hub: https://hub.docker.com
- Test manually: `docker pull your-image-name`

**❌ Build fails with "ISO not found"**
- Check internet connection (downloads 4GB Ubuntu ISO)
- Ensure sufficient disk space (10GB free)
- Try building again (sometimes network issues)

**❌ "APPLIANCE_NAME must be lowercase"**
- Use single lowercase word: `nginx` not `NGINX` or `nginx-server`
- No spaces, dashes, or special characters

**❌ Build takes too long**
- First build downloads Ubuntu ISO (4GB) - this is normal
- Subsequent builds are faster (ISO is cached)
- Building on SSD is much faster than HDD

### Getting Help

1. **Check generated files**: Look at `../appliances/yourapp/README.md`
2. **Verify configuration**: Check your `.env` file for typos
3. **Test Docker image**: Try `docker pull your-image` manually
4. **OpenNebula community**: Ask in forums or GitHub issues

---

## 🎉 Success!

**Congratulations!** You've created a complete OpenNebula appliance from a Docker container.

### What You've Accomplished:
✅ **Generated 13+ files** automatically from your Docker configuration
✅ **Created complete appliance** with proper OpenNebula integration
✅ **Built VM image** ready for deployment (if you ran the build)
✅ **Made your app available** to the OpenNebula community

### Your Appliance Includes:
- 🖥️ **Ubuntu 22.04 LTS** base operating system
- 🐳 **Docker Engine** pre-installed and configured
- 🎯 **Your Docker container** starting automatically on boot
- 🖱️ **VNC desktop access** for GUI interaction
- 🔐 **SSH access** with OpenNebula key authentication
- ⚙️ **Configurable parameters** through OpenNebula interface
- 📊 **Container monitoring** and management tools
- 🔄 **Automatic restart** policies for your container

### Next Steps:
- 🔄 **Create more appliances**: Just make new `.env` files and run the generator
- 🌐 **Deploy your appliance**: Use the `.qcow2` file on any OpenNebula cloud
- 📤 **Share with community**: Submit to OpenNebula marketplace
- 🛠️ **Customize further**: Edit the generated files for advanced configurations

### Quick Reference:
```bash
# Create new appliance
nano myapp.env
./generate-docker-appliance.sh myapp.env

# Build VM image
cd ../apps-code/community-apps
# Add myapp to SERVICES in Makefile.config
make myapp
```

🚀 **You've mastered Docker appliance creation for OpenNebula!**

---

## 📊 Summary

**Time Investment**: 15-30 minutes
**Result**: Complete, production-ready OpenNebula appliance
**Skills Gained**: Docker containerization + OpenNebula cloud deployment
**Files Generated**: 13+ files including VM image, documentation, tests

**You can now turn ANY Docker container into an OpenNebula appliance!** 🌟
