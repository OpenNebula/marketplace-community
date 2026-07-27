# Creating OpenNebula Appliances - Automatic Method

**Quick appliance creation using the generator script**

---

## 📖 Introduction

This guide shows you how to quickly create OpenNebula appliances from Docker containers using an automated generator script. The generator creates all necessary files following the structure used by the appliances already in this repository.

**What you'll create:**
- A VM image (QCOW2 format) with Docker on the base OS you select (`BASE_OS`, default Ubuntu 22.04 minimal)
- Automatic Docker container startup on VM boot
- SSH access using the public key injected by OpenNebula context (`SSH_PUBLIC_KEY`) — password login is disabled and the root password is locked in the shipped image
- Console and serial console auto-login
- OpenNebula context integration for runtime configuration

**Time required:** ~1 minute for generation + ~2 minutes for building (plus a one-time ~2-3 minute base OS build)

---

## ✅ Prerequisites

- **Linux host** (Ubuntu 22.04+ recommended). The generator uses GNU `sed -i`; it does **not** run on macOS/BSD.
- **Root access** — the image build uses `chroot` and `/dev/kvm`, so `make` must be run as root (`sudo`).
- **Hardware**: KVM enabled (`/dev/kvm` present), 8 GB+ RAM, 40 GB+ free disk.

Install the build dependencies (official list:
<https://github.com/OpenNebula/one-apps/wiki/tool_reqs>):

```bash
sudo apt update
sudo apt install -y \
  bash cloud-utils cloud-image-utils genisoimage git gnupg lsb-release \
  libguestfs0 libguestfs-tools make qemu-utils qemu-system-x86 \
  rpm rsync ruby wget

# Ruby gems required to build the one-context packages
sudo gem install --no-document backports fpm
```

Install Packer (>= 1.9.4) from HashiCorp — it is **not** in the Ubuntu archive:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer
packer version
```

> `fpm`, `rpm` and `cloud-image-utils` (which provides `cloud-localds`) are the
> three that are almost never already installed and whose absence fails the
> build with a confusing error.

---

## 🚀 Quick Start

### Step 1: Clone Repository

```bash
git clone https://github.com/OpenNebula/marketplace-community.git
cd marketplace-community

# REQUIRED: everything the build needs lives behind the one-apps submodule.
# Without this, apps-code/one-apps is empty and
# apps-code/community-apps/packer/build.sh is a dangling symlink, so
# `make <name>` fails immediately.
git submodule update --init --recursive
```

### Step 2: Build the Base OS Image (once per host)

`make <name>` in `community-apps` **never** builds the base image for you: the
generated Packer template consumes `apps-code/one-apps/export/<BASE_OS>.qcow2`
and fails if it is missing. Build it once (the default `BASE_OS` is
`ubuntu2204min`):

```bash
cd apps-code/one-apps
sudo make ubuntu2204min      # ~2-3 min -> export/ubuntu2204min.qcow2
cd ../..
```

This also builds the one-context packages, which is why `fpm` and `rpm` are
required. Docker is **not** needed on the build host. The base image is reused
by every appliance you generate afterwards.

### Step 3: Create Configuration File

Create a `.env` file with your Docker container details:

```bash
cd docs/automatic-appliance-tutorial

cat > myapp.env << 'ENVEOF'
# Required variables
DOCKER_IMAGE="your-docker-image:1.2.3"   # must be a pinned tag, not :latest
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
BASE_OS="ubuntu2204min"
ENVEOF
```

### Step 4: Run Generator

```bash
./generate-docker-appliance.sh myapp.env --no-build
```

The generator will:
1. Create all appliance files
2. Generate the Packer build definition
3. Register the appliance in `apps-code/community-apps/Makefile.config`
   (`SERVICES` list) so that `make <name>` works
4. Prompt you to build the image immediately — **only when stdin is a TTY**, and
   only if you did not pass `--no-build`. Piped / CI / `ssh host bash -s` runs
   skip the prompt and exit 0.

**Flags:**

| Flag | Effect |
|------|--------|
| `--no-build` | Generate only; never prompt, never build. Use this for CI and non-interactive runs. |
| `--force` | Regenerate over an existing appliance. Without it the generator refuses to overwrite `appliances/<name>/` or `packer/<name>/` and exits 1. `--force` wipes both directories first (a new appliance UUID is generated). |
| `-h`, `--help` | Show usage and exit. |

```bash
# non-interactive / CI
./generate-docker-appliance.sh myapp.env --no-build

# regenerate an appliance you already created
./generate-docker-appliance.sh myapp.env --force
```

**Output:**
```
[INFO] 🚀 Loading configuration from myapp.env
[INFO] 🎯 Generating complete appliance: myapp (MyApp)
[INFO] 📁 Creating directory structure...
[SUCCESS] Directory structure created
[INFO] 📝 Generating metadata.yaml...
[INFO] 📝 Generating <uuid>.yaml...
[SUCCESS] Metadata files generated
[INFO] 📝 Generating README.md...
[SUCCESS] README.md generated
[INFO] 📝 Generating appliance.sh installation script...
[SUCCESS] appliance.sh generated
[INFO] 📝 Generating Packer configuration files...
[INFO] 📝 Generating additional required files...
[SUCCESS] Additional files generated
[SUCCESS] Packer configuration files generated
[INFO] 📝 Adding 'myapp' to Makefile.config SERVICES list...
[SUCCESS]   ✅ Added 'myapp' to SERVICES list
[INFO] 🎉 Appliance 'myapp' generated successfully!
```

### About the image size

The generated `service_install()` installs `linux-image-generic` plus the
matching `linux-modules-extra` and makes it the default GRUB entry. The minimal
base images ship a `-kvm` kernel with no Virtual Terminal support, which makes
the Sunstone VNC console come up as a black screen; the generic kernel fixes
that. It also roughly doubles the exported qcow2: a generated NGINX appliance
measures ~1.4 GB, against ~0.6 GB for an equivalent appliance built without the
kernel swap.

If your appliance is headless and you do not care about the VNC console, delete
that block from `appliances/<name>/appliance.sh` before building and the image
shrinks accordingly.

### Step 5: Build the Appliance Image

Step 4 above passes `--no-build`, so the image has not been built yet. (If you
run the generator *without* `--no-build` on a TTY and answer 'y' to its build
prompt, it does this for you — that path initialises the submodule and builds
the base image first.) To build it yourself:

```bash
cd ../../apps-code/community-apps
sudo make myapp
```

**Build time:** ~2 minutes. The build boots the base qcow2, installs Docker CE,
and **pulls your Docker image into the qcow2 at build time**. No Ubuntu ISO is
downloaded.

**Output file:** `apps-code/community-apps/export/myapp.qcow2`

---

## 📋 Configuration Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `DOCKER_IMAGE` | Yes | Docker image name, pinned tag or digest | `nginx:alpine` |
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
| `BASE_OS` | No | Base OS image to build on (default `ubuntu2204min`) | `ubuntu2404min` |
| `DISK_SIZE` | No | Appliance virtual disk size in MiB (default `20480`) | `20480` |

**`BASE_OS`** is set inside the `.env` file, not on the command line. Supported
values (anything else is rejected with exit 1):

`ubuntu2204min` `ubuntu2204` `ubuntu2404min` `ubuntu2404` `debian12` `debian11`
`alma8` `alma9` `rocky8` `rocky9` `opensuse15`

Whichever value you pick, `apps-code/one-apps/export/<BASE_OS>.qcow2` must be
built before `make <name>` (see Step 2).

**`DISK_SIZE`** is the appliance's virtual disk in MiB. Packer can only *grow*
the base image, so it must be at least as large as the base you selected — the
bases differ widely (`ubuntu2204min` is 2.2 GiB, `alma9` is 10 GiB). Asking for
less aborts the build with:

```
Error creating hard drive: QemuImg error: qemu-img:
Use the --shrink option to perform a shrink operation.
```

The default of `20480` clears every supported base. qcow2 is sparse, so a
generous virtual size does not make the exported file bigger.

**`DOCKER_IMAGE` must be pinned.** An untagged image or an explicit `:latest`
tag is rejected — use a released tag (`nginx:1.27-alpine`) or a digest
(`nginx@sha256:...`).

**`DEFAULT_ENV_VARS` is baked into the image.** Never put a real secret there.
Secrets (database passwords, API keys) belong in the `ONEAPP_CONTAINER_ENV`
context variable, supplied at instantiation time.

---

## 📁 Generated Files

The generator creates:

```
marketplace-community/
├── appliances/myapp/
│   ├── appliance.sh              # install / configure / bootstrap logic
│   ├── metadata.yaml             # appliance descriptor (:app: / :one: / :infra:)
│   ├── <uuid>.yaml               # marketplace appliance definition
│   ├── context.yaml              # default context values used by the tests
│   ├── README.md                 # documentation
│   ├── CHANGELOG.md              # version history
│   ├── tests.yaml                # list of test files
│   └── tests/
│       └── 00-myapp_basic.rb     # RSpec certification test
├── apps-code/community-apps/packer/myapp/
│   ├── myapp.pkr.hcl             # Packer build definition
│   ├── variables.pkr.hcl         # Packer variables
│   ├── common.pkr.hcl            # symlink to one-apps/packer/common.pkr.hcl
│   ├── 81-configure-ssh.sh       # re-hardens sshd (key-only) during the build
│   ├── 82-configure-context.sh   # installs the one-context hooks
│   ├── gen_context               # build-time context ISO generator
│   ├── postprocess.sh            # post-build hook
│   └── .gitignore                # ignores transient build artifacts only
└── apps-code/community-apps/Makefile.config   # MODIFIED: myapp appended to SERVICES
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

`make` treats `export/myapp.qcow2` as an up-to-date target, so a plain
`make myapp` is a no-op once the image exists. Delete just your own image and
rebuild:

```bash
cd apps-code/community-apps
sudo rm -f export/myapp.qcow2
sudo make myapp
```

Do not use `make clean` for this: it is `rm -rf export/*` and wipes every
appliance image you have built, not only `myapp`.

---

## 📦 Examples

The four `.env` files in `docs/automatic-appliance-tutorial/examples/` have each
been generated, built and booted. The blocks below are trimmed versions of them
(`APP_DESCRIPTION` and `APP_FEATURES` are optional and get sensible defaults);
use the shipped files verbatim if you want the exact tested configuration.

### NGINX Web Server

```bash
cat > nginx.env << 'EOF'
DOCKER_IMAGE="nginx:alpine"
APPLIANCE_NAME="nginx"
APP_NAME="NGINX Web Server"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="80:80,443:443"
# No default volumes: mounting empty host directories over the image's own
# /etc/nginx/conf.d (default.conf) or /usr/share/nginx/html hides the image's
# built-in config and default page, leaving nginx with nothing to serve.
DEFAULT_VOLUMES=""
APP_PORT="80"
WEB_INTERFACE="true"
EOF

./generate-docker-appliance.sh nginx.env --no-build
```

### Node-RED

```bash
cat > nodered.env << 'EOF'
DOCKER_IMAGE="nodered/node-red:5.0.1"
APPLIANCE_NAME="nodered"
APP_NAME="Node-Red"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="1880:1880"
DEFAULT_VOLUMES="/data:/data"
APP_PORT="1880"
WEB_INTERFACE="true"
EOF

./generate-docker-appliance.sh nodered.env --no-build
```

The tag is pinned to match `docs/automatic-appliance-tutorial/examples/nodered.env`:
`nodered/node-red:latest` is rejected by the generator.

### PostgreSQL Database

```bash
cat > postgres.env << 'EOF'
DOCKER_IMAGE="postgres:15"
APPLIANCE_NAME="postgres"
APP_NAME="PostgreSQL Database"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="5432:5432"
DEFAULT_ENV_VARS="POSTGRES_DB=appdb,POSTGRES_USER=postgres"
DEFAULT_VOLUMES="/var/lib/postgresql/data:/var/lib/postgresql/data"
APP_PORT="5432"
WEB_INTERFACE="false"
EOF

./generate-docker-appliance.sh postgres.env --no-build
```

**Note:** `POSTGRES_PASSWORD` is deliberately absent from `DEFAULT_ENV_VARS` —
anything you put there is baked into the published image. PostgreSQL refuses to
initialise without it, so it **must** be supplied at instantiation through the
context variable, e.g.
`ONEAPP_CONTAINER_ENV = "POSTGRES_PASSWORD=<your-password>"` in the VM
template's `CONTEXT` section.

### Redis Cache

```bash
cat > redis.env << 'EOF'
DOCKER_IMAGE="redis:alpine"
APPLIANCE_NAME="redis"
APP_NAME="Redis Cache"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="6379:6379"
DEFAULT_VOLUMES="/data:/data"
APP_PORT="6379"
WEB_INTERFACE="false"
EOF

./generate-docker-appliance.sh redis.env --no-build
```

**Note:** the generator refuses two classes of configuration outright, so they
can never appear in a working example:

- `DOCKER_IMAGE` with an explicit `:latest` tag, or with no tag at all (both
  resolve to a mutable tag). Pin a released tag (`nginx:1.27-alpine`) or a
  digest (`nginx@sha256:...`).
- `DEFAULT_VOLUMES` mapping a sensitive host path — `/var/run/docker.sock`,
  `/run/docker.sock`, `/`, `/root`, `/proc`, `/sys`, `/dev`, `/boot`,
  `/var/run`, `/run`, `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`,
  `/var/lib/docker`. These are container-escape vectors. Docker-in-Docker
  style appliances (e.g. Nextcloud All-in-One, which needs the Docker socket)
  cannot be produced by this generator.

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
  SET_HOSTNAME = "$NAME",
  ONEAPP_CONTAINER_NAME = "myapp-container",
  ONEAPP_CONTAINER_PORTS = "8080:8080",
  ONEAPP_CONTAINER_ENV = "",
  ONEAPP_CONTAINER_VOLUMES = ""
]
GRAPHICS = [
  TYPE = "VNC",
  LISTEN = "0.0.0.0"
]
EOF

# Create the template
onetemplate create myapp-template.txt
```

**Note:** the `ONEAPP_CONTAINER_*` variables are how the appliance is configured
at instantiation; omit them and the container falls back to the defaults baked
in at generation time. Container environment variables may carry secrets (DB
passwords, API keys), so always supply them here via `ONEAPP_CONTAINER_ENV`
rather than committing them into the appliance files.

**List separators.** `ONEAPP_CONTAINER_PORTS`, `ONEAPP_CONTAINER_ENV` and
`ONEAPP_CONTAINER_VOLUMES` hold lists. The appliance accepts **either `,` or `;`**
between items, so all of these are equivalent:

```
ONEAPP_CONTAINER_PORTS = "80:80,443:443"
ONEAPP_CONTAINER_PORTS = "80:80;443:443"
```

Use whichever reads better in Sunstone. One place where it matters: the
certification harness (`lib/community/app_handler.rb`) joins the
`metadata.yaml` `:params:` entries with commas and hands the result to
`onetemplate instantiate --context`, and the CLI splits that string on commas
regardless of quoting. A comma *inside* a value is therefore truncated there
(`"80:80,443:443"` arrives as `"80:80,"`). For that reason the generator writes
the `:params:` defaults in `metadata.yaml` with `;`, and you should keep it that
way. The same caution applies whenever you pass a list through
`--context` on the command line — prefer `;` there.

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

The deployed appliance accepts **only** the public key delivered through the
`SSH_PUBLIC_KEY` context variable. Password authentication is disabled and the
root password is locked, so make sure your key is in the template's CONTEXT
before instantiating.

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
# From the OpenNebula host, using the private key matching SSH_PUBLIC_KEY
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
- ✅ SSH access works with the context-injected key (`ssh root@<VM_IP>`); password login is correctly refused
- ✅ Console auto-login works (check via VNC)

### 3. Run the Certification Tests

The generator writes an rspec test at
`appliances/myapp/tests/00-myapp_basic.rb` and lists it in
`appliances/myapp/tests.yaml`. The community harness
(`lib/community/app_readiness.rb`) creates the image, instantiates a VM from
your `metadata.yaml` `:params:` and runs the test against it. On the frontend:

```bash
# rspec is not part of the OpenNebula gem set; install it once
sudo gem install --no-document rspec

# the image must be readable by oneadmin (oned runs as oneadmin)
sudo cp apps-code/community-apps/export/myapp.qcow2 /var/tmp/
sudo chmod 644 /var/tmp/myapp.qcow2

sudo -u oneadmin env IMAGES_URL=/var/tmp/ \
  bash -c 'cd lib/community && mkdir -p results && ./app_readiness.rb myapp'
```

Expected output:

```
Appliance Certification
  docker engine is active
  MyApp image (myimage:1.2.3) is present
  MyApp container (myapp-container) is running

3 examples, 0 failures
```

Requirements that are easy to miss:

- **Run as `oneadmin`.** The harness reaches the VM with `ssh root@<vm-ip>` and
  the VM only trusts the key contextualization injected from
  `$USER[SSH_PUBLIC_KEY]`, which is oneadmin's. Running as root gives
  `Permission denied (publickey)` and every example fails with
  `reached timeout ... reachable?`.
- **`IMAGES_URL` must be readable by oneadmin.** A path under `/root` fails with
  `Cannot parse image SIZE: ... (Permission denied)`.
- **A VM template named `base` must exist** (`defaults.yaml` sets
  `:template: base`); the harness instantiates it with `--disk <image>` plus the
  context built from `metadata.yaml`.

Results are written to `lib/community/results/myapp/`.

---

## 📤 Next Steps

### 1. Add a Logo

Create a 256x256 PNG logo for your appliance to display in the OpenNebula Sunstone UI.

#### Step 1: Create or Download the Logo

**Option A: Download from the project's official source**
```bash
# Replace the URL with the official logo of the application you are packaging
wget -O /tmp/app-logo.png "https://example.com/path/to/official-logo.png"
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

### 2. Submit to Marketplace

Once your appliance is tested and working, submit it to the OpenNebula Marketplace:

#### Create Fork and Branch

```bash
# Fork the repository on GitHub first (https://github.com/OpenNebula/marketplace-community)
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/marketplace-community.git
cd marketplace-community
git submodule update --init --recursive

# Create feature branch
git checkout -b feature/add-myapp-appliance
```

#### Add Your Files

```bash
git add appliances/myapp/
git add apps-code/community-apps/packer/myapp/
# REQUIRED: the generator appended your appliance to the SERVICES list.
# Without this file `make myapp` fails with "No rule to make target",
# and the PR cannot be built.
git add apps-code/community-apps/Makefile.config
git add logos/myapp.png

git commit -m "Add MyApp appliance

- Docker container with automatic startup
- OpenNebula context integration
- SSH (key-only) and console access
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
  - ONEAPP_CONTAINER_NAME
  - ONEAPP_CONTAINER_PORTS
  - ONEAPP_CONTAINER_ENV
  - ONEAPP_CONTAINER_VOLUMES

## Testing

- ✅ Built successfully with Packer
- ✅ Deployed to OpenNebula
- ✅ Container starts automatically
- ✅ SSH access works with the OpenNebula context-injected key (password login disabled)
- ✅ Console auto-login works
- ✅ Application accessible on configured ports

## Files Added

- `appliances/myapp/` - Appliance definition files
- `apps-code/community-apps/packer/myapp/` - Packer build configuration
- `apps-code/community-apps/Makefile.config` - appliance added to SERVICES
- `logos/myapp.png` - Appliance logo

## Checklist

- [x] Appliance builds successfully
- [x] Appliance tested on OpenNebula
- [x] Documentation included (README.md)
- [x] Logo added (256x256 PNG)
- [x] Follows community appliance structure
- [x] Docker image pinned to an immutable tag or digest
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

**Problem:** `Refusing to overwrite. Re-run with --force to replace it.`  
**Solution:** The appliance already exists. Re-run with `--force` (it wipes
`appliances/<name>/` and `packer/<name>/` first and assigns a new UUID).

**Problem:** The generator aborts with a `sed` error  
**Solution:** You are not on Linux. The generator requires GNU `sed -i`; run it
on a Linux host.

### Build Fails

**Problem:** Packer build fails  
**Solution:** Check Packer logs

```bash
cd apps-code/community-apps
sudo make myapp 2>&1 | tee build.log
```

Common issues:
- Base image missing — build it first: `cd apps-code/one-apps && sudo make ubuntu2204min`
- Not running as root, or `/dev/kvm` is unavailable
- Missing build dependencies: `fpm` (ruby gem), `rpm`, `cloud-image-utils` (provides `cloud-localds`)
- Submodule not initialised — `apps-code/community-apps/packer/build.sh` is a dangling symlink until you run `git submodule update --init --recursive`
- Insufficient disk space (40 GB+ free needed)
- Docker image doesn't exist, is private, or was rejected for using a mutable `:latest` tag

### Container Doesn't Start

**Problem:** Container fails to start on VM boot  
**Solution:** Check the generated `appliance.sh` for correct Docker image name

```bash
# Verify Docker image name in appliance.sh
grep "DOCKER_IMAGE=" appliances/myapp/appliance.sh
```

### Permission Issues

**Problem:** Container can't write to volumes  
**Solution:** When the appliance has to **create** a host directory for a volume
mount, it chowns that newly created directory to the UID/GID the container image
runs as (resolved from the image itself), which is what makes volumes work for
images that run unprivileged. It deliberately never touches a **pre-existing**
host directory — no recursive chown of an existing tree.

So if the mount point already exists on the host with the wrong ownership, fix
it yourself in the `service_install()` function of
`appliances/myapp/appliance.sh`:

```bash
# In service_install() function
mkdir -p /data
chown 1000:1000 /data  # use your container's UID:GID
```

Then rebuild the image for the change to take effect (see
"Rebuild After Changes" — deleting `export/myapp.qcow2` first is required,
otherwise `make` considers the target up to date and does nothing).

---

## 💡 Tips

- **Start simple** - Begin with minimal configuration, add features incrementally
- **Use official images** - Prefer official Docker images from Docker Hub
- **Pin the tag** - `:latest` and untagged images are rejected; a pinned tag or digest keeps rebuilds reproducible
- **Test the Docker image first** - Run `docker run` locally before generating appliance
- **Check examples** - Study the example .env files for reference
- **Volume permissions** - A host directory that already exists is never re-owned by the appliance; make sure its ownership matches the container's UID
- **Don't shadow image content** - Mounting an empty host directory over a path the image populates (e.g. nginx's `/etc/nginx/conf.d`) hides the image's own files
- **Secrets** - Pass them at instantiation via `ONEAPP_CONTAINER_ENV`, never in `DEFAULT_ENV_VARS`
- **Port conflicts** - Ensure ports don't conflict with system services

---

## 📖 Additional Resources

- [Manual Appliance Guide](MANUAL_APPLIANCE_GUIDE.md) - For advanced customization
- [one-apps build requirements](https://github.com/OpenNebula/one-apps/wiki/tool_reqs)
- [OpenNebula Documentation](https://docs.opennebula.io/)
- [Docker Hub](https://hub.docker.com/)
- [Packer Documentation](https://www.packer.io/docs)
- [OpenNebula Marketplace](https://marketplace.opennebula.io/)
