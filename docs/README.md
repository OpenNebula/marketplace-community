# OpenNebula Appliance Creation Guides

Welcome to the OpenNebula appliance creation documentation! This guide will help you create Docker-based appliances for the OpenNebula Community Marketplace.

---

## 📚 Available Guides

Choose the approach that best fits your needs:

### 🤖 [Automatic Appliance Guide](AUTOMATIC_APPLIANCE_GUIDE.md)

**Best for:** Quick appliance creation, beginners, standard Docker containers

**Time:** ~5 minutes for generation + 15-20 minutes for building

**Features:**
- ✅ Automated file generation from simple configuration
- ✅ Proven Phoenix RTOS/Node-RED structure
- ✅ Built-in examples (NGINX, Node-RED, PostgreSQL, Redis)
- ✅ Automatic build integration
- ✅ Minimal configuration required

**Quick Start:**
```bash
cd docs/automatic-appliance-tutorial
cat > myapp.env << 'EOF'
DOCKER_IMAGE="nginx:alpine"
APPLIANCE_NAME="nginx"
APP_NAME="NGINX"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="80:80"
APP_PORT="80"
WEB_INTERFACE="true"
EOF

./generate-docker-appliance.sh myapp.env
```

---

### ✍️ [Manual Appliance Guide](MANUAL_APPLIANCE_GUIDE.md)

**Best for:** Custom appliances, advanced users, special requirements

**Time:** ~30-45 minutes for creation + 15-20 minutes for building

**Features:**
- ✅ Complete control over all files
- ✅ Custom installation logic
- ✅ Advanced Docker configurations
- ✅ Special system requirements
- ✅ Deep understanding of appliance structure

**Quick Start:**
```bash
mkdir -p appliances/myapp
cd appliances/myapp
# Create metadata.yaml, appliance.sh, README.md, etc.
# See the manual guide for detailed instructions
```

---

## 🎯 Which Guide Should I Use?

| Scenario | Recommended Guide |
|----------|-------------------|
| First time creating an appliance | **Automatic** |
| Standard Docker container | **Automatic** |
| Need quick results | **Automatic** |
| Want to learn the structure | **Automatic** (then study generated files) |
| Need custom installation steps | **Manual** |
| Complex system requirements | **Manual** |
| Non-standard Docker setup | **Manual** |
| Want full control | **Manual** |

**Pro Tip:** Even if you need customization, start with the automatic generator to get a working base, then modify the generated files!

---

## 📖 What You'll Create

Both guides help you create:

- **VM Image (QCOW2)** - Ubuntu 22.04 LTS with Docker pre-installed
- **Docker Container** - Your application running in a container
- **Automatic Startup** - Container starts automatically on VM boot
- **SSH Access** - Password (opennebula) and key authentication
- **Console Access** - Auto-login to root user
- **OpenNebula Context** - Runtime configuration via context variables
- **VNC Access** - Graphical console access

---

## 🚀 Quick Comparison

| Feature | Automatic | Manual |
|---------|-----------|--------|
| **Time to create** | 5 minutes | 30-45 minutes |
| **Difficulty** | Easy | Moderate |
| **Customization** | Limited | Full |
| **Learning curve** | Low | Medium |
| **Best for** | Standard containers | Custom requirements |
| **Files generated** | All files | You create all files |
| **Examples included** | Yes (4 examples) | Template provided |
| **Build integration** | Yes | Manual |

---

## 📦 Example Appliances

Both guides can create appliances for:

- **Web Servers** - NGINX, Apache, Caddy
- **Databases** - PostgreSQL, MySQL, MongoDB, Redis
- **Development Tools** - Node-RED, Jupyter, VS Code Server
- **Monitoring** - Grafana, Prometheus, Netdata
- **Automation** - n8n, Airflow, Jenkins
- **And more!** - Any Docker container

---

## 🛠️ Prerequisites

Both guides require:

- Linux system (Ubuntu 22.04+ recommended)
- Git
- Packer (for building images)
- QEMU/KVM (for building images)

```bash
sudo apt update
sudo apt install -y git qemu-kvm qemu-utils
```

---

## 📚 Additional Resources

- [OpenNebula Documentation](https://docs.opennebula.io/)
- [OpenNebula Marketplace](https://marketplace.opennebula.io/)
- [Docker Hub](https://hub.docker.com/)
- [Packer Documentation](https://www.packer.io/docs)
- [OpenNebula Community Forum](https://forum.opennebula.io/)

