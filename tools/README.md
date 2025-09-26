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
