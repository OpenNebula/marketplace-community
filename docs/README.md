# OpenNebula Appliance Creation Guides

Welcome to the OpenNebula appliance creation documentation! This guide will help you create Docker-based appliances for the OpenNebula Community Marketplace.

> **Read the Prerequisites section below first.** Cloning the repository,
> initializing the `one-apps` submodule and building the base OS image once are mandatory:
> without them `make <appliance>` fails immediately, no matter which guide you follow.

---

## 🛠️ Prerequisites

The image build runs Packer + QEMU/KVM and chroots into the guest, so it must run
**on a Linux host, as root**, with hardware virtualization available:

- Linux (Ubuntu 22.04+ recommended). macOS/BSD will **not** work — the generator uses GNU `sed -i`.
- `root` privileges (the build chroots) and access to `/dev/kvm`
- At least 8 GB RAM and 40 GB free disk
- Packer >= 1.9.4

### 1. Clone the repository and initialize the submodule

```bash
# Clone the repository AND initialise the one-apps submodule (without this,
# apps-code/community-apps/packer/build.sh is a dangling symlink and every build fails)
git clone https://github.com/OpenNebula/marketplace-community.git
cd marketplace-community
git submodule update --init --recursive
```

### 2. Install the build prerequisites

Full authoritative list: <https://github.com/OpenNebula/one-apps/wiki/tool_reqs>

```bash
# Install the build prerequisites (Ubuntu/Debian).
sudo apt update
sudo apt install -y make ruby rpm rsync genisoimage cloud-utils cloud-image-utils \
                    qemu-utils qemu-system-x86 libguestfs-tools
sudo gem install --no-document backports fpm
```

`fpm` (a Ruby gem), `rpm` and `cloud-image-utils` (which provides `cloud-localds`) are **not**
present on a stock Ubuntu host, and the one-apps context-package build fails without them.

Packer >= 1.9.4 is **not** in the Ubuntu archive — install HashiCorp's package:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer
```

### 3. Build the base OS image (once)

Every generated `<name>.pkr.hcl` boots the base image from `../one-apps/export/<BASE_OS>.qcow2`,
and `make <appliance>` in `apps-code/community-apps` never builds it for you, so it must exist
first:

```bash
# Build the base OS image ONCE (~2.5 minutes). Every appliance is built on top of it.
cd apps-code/one-apps
sudo make ubuntu2204min          # -> apps-code/one-apps/export/ubuntu2204min.qcow2
cd ../..
```

If you set a different `BASE_OS` in your `.env`, build that base image instead
(`ubuntu2204`, `ubuntu2404min`, `ubuntu2404`, `debian12`, `debian11`, `alma8`, `alma9`,
`rocky8`, `rocky9`, `opensuse15`).

> The generator's interactive build prompt will initialize the submodule and build the base
> image for you *if you answer `y`* at a real terminal. With `--no-build`, in a non-interactive
> session (CI, `ssh host 'bash -s'`), or when you run `make <appliance>` yourself, it will not —
> do steps 1-3 above first.

---

## 📚 Available Guides

Choose the approach that best fits your needs:

### 🤖 [Automatic Appliance Guide](AUTOMATIC_APPLIANCE_GUIDE.md)

**Best for:** Quick appliance creation, beginners, standard Docker containers

**Time:** seconds to generate + ~2 minutes to build the appliance image
(plus a one-time ~2.5 minute base OS image build)

**Features:**
- ✅ Automated file generation from a simple `.env` configuration
- ✅ Produces the complete buildable layout: `appliances/<name>/`, `apps-code/community-apps/packer/<name>/`,
  and the `SERVICES` registration in `apps-code/community-apps/Makefile.config`
- ✅ Working examples in `examples/` (NGINX, PostgreSQL, Redis, Node-RED) — every `DOCKER_IMAGE`
  is pinned to a fixed tag, because the generator rejects `:latest` and untagged images
- ✅ Generates the community RSpec test skeleton
- ✅ Minimal configuration required

**Quick Start:**

> Finish the **Prerequisites** section above first — submodule init and the base image
> build are mandatory.

```bash
cd docs/automatic-appliance-tutorial

cat > myapp.env << 'EOF'
# DOCKER_IMAGE must be pinned: ':latest' and untagged images are rejected
DOCKER_IMAGE="nginx:alpine"
APPLIANCE_NAME="nginx"
APP_NAME="NGINX"
PUBLISHER_NAME="Your Name"
PUBLISHER_EMAIL="your@email.com"
DEFAULT_PORTS="80:80"
APP_PORT="80"
WEB_INTERFACE="true"
# Optional, default ubuntu2204min. One of: ubuntu2204min ubuntu2204 ubuntu2404min
# ubuntu2404 debian12 debian11 alma8 alma9 rocky8 rocky9 opensuse15
BASE_OS="ubuntu2204min"
EOF

# Generate the appliance files.
#   --no-build  skip the interactive "build now?" prompt (use for CI/scripted runs)
#   --force     regenerate over an existing appliance of the same name; without it
#               the generator refuses to overwrite and exits 1
sudo ./generate-docker-appliance.sh myapp.env --no-build

# Build the image (~2 min). The make target is APPLIANCE_NAME.
cd ../../apps-code/community-apps
sudo make nginx
# -> apps-code/community-apps/export/nginx.qcow2
```

Ready-made configs live in `docs/automatic-appliance-tutorial/examples/`, e.g.

```bash
cd docs/automatic-appliance-tutorial
sudo ./generate-docker-appliance.sh examples/nginx.env --no-build
```

**Full generator CLI:**

```text
./generate-docker-appliance.sh <config.env> [--no-build] [--force] [-h|--help]

  --no-build   Do not offer to build after generating. Required for
               non-interactive/CI use.
  --force      Regenerate over an existing appliance of the same name; the previous
               appliance directory is wiped first. Without it the generator refuses
               to overwrite and exits 1.
  -h, --help   Show usage and exit.
```

`BASE_OS` is not a flag — it is set **inside** the `.env` file and defaults to
`ubuntu2204min`. Supported values: `ubuntu2204min`, `ubuntu2204`, `ubuntu2404min`,
`ubuntu2404`, `debian12`, `debian11`, `alma8`, `alma9`, `rocky8`, `rocky9`, `opensuse15`.

**Files the generator produces:**

```text
appliances/<name>/appliance.sh
appliances/<name>/metadata.yaml
appliances/<name>/<uuid>.yaml
appliances/<name>/context.yaml
appliances/<name>/README.md
appliances/<name>/CHANGELOG.md
appliances/<name>/tests.yaml
appliances/<name>/tests/00-<name>_basic.rb
apps-code/community-apps/packer/<name>/<name>.pkr.hcl
apps-code/community-apps/packer/<name>/variables.pkr.hcl
apps-code/community-apps/packer/<name>/common.pkr.hcl   (symlink into one-apps)
apps-code/community-apps/packer/<name>/gen_context
apps-code/community-apps/packer/<name>/81-configure-ssh.sh
apps-code/community-apps/packer/<name>/82-configure-context.sh
apps-code/community-apps/packer/<name>/postprocess.sh
apps-code/community-apps/packer/<name>/.gitignore
(modified) apps-code/community-apps/Makefile.config
```

Everything above, **including the `Makefile.config` change**, must be part of your pull
request — otherwise `make <name>` is not a valid target for reviewers. The only exceptions
are the `.gitignore`d transient build artifacts (`context/`, `context.sh`, `*-context.iso`).

---

### ✍️ [Manual Appliance Guide](MANUAL_APPLIANCE_GUIDE.md)

**Best for:** Custom appliances, advanced users, special requirements

**Time:** ~30-45 minutes of authoring + ~2 minutes to build the appliance image

**Features:**
- ✅ Complete control over all files
- ✅ Custom installation logic
- ✅ Advanced Docker configurations
- ✅ Special system requirements
- ✅ Deep understanding of appliance structure

**Quick Start:**
```bash
# NOTE: an appliance directory alone is NOT buildable. `make <name>` also requires:
#   apps-code/community-apps/packer/<name>/<name>.pkr.hcl
#   apps-code/community-apps/packer/<name>/variables.pkr.hcl
#   apps-code/community-apps/packer/<name>/{gen_context,81-configure-ssh.sh,82-configure-context.sh,postprocess.sh}
#   apps-code/community-apps/packer/<name>/common.pkr.hcl -> ../../../one-apps/packer/common.pkr.hcl
#   <name> appended to the SERVICES := line in apps-code/community-apps/Makefile.config
#
# Recommended even for custom appliances: generate a buildable skeleton first,
# then edit it by hand.
cd docs/automatic-appliance-tutorial
sudo ./generate-docker-appliance.sh myapp.env --no-build
$EDITOR ../../appliances/myapp/appliance.sh
$EDITOR ../../apps-code/community-apps/packer/myapp/myapp.pkr.hcl
```

> ⚠️ **Known gap in [MANUAL_APPLIANCE_GUIDE.md](MANUAL_APPLIANCE_GUIDE.md):** its Step 5
> describes a standalone, ISO-based `myapp.pkr.hcl` that does not declare the variables
> `packer/build.sh` passes (`appliance_name`, `version`, `input_dir`, `output_dir`,
> `headless`, `arch`), and the guide never registers the appliance in the
> `SERVICES :=` line of `apps-code/community-apps/Makefile.config`. Its Step 7 `make myapp`
> therefore cannot work as written. Step 5 also has you write a
> `myapp.auto.pkrvars.hcl`; no such file exists in a real appliance — variables are
> declared in `variables.pkr.hcl` and passed in by `packer/build.sh`. Generate the
> skeleton as shown above and edit it instead of hand-writing the Packer template
> from scratch.

---

## 🎯 Which Guide Should I Use?

| Scenario | Recommended Guide |
|----------|-------------------|
| First time creating an appliance | **Automatic** |
| Standard Docker container | **Automatic** |
| Need quick results | **Automatic** |
| Want to learn the structure | **Automatic** (then study generated files) |
| Need custom installation steps | **Automatic**, then edit the generated files |
| Complex system requirements | **Manual** |
| Non-standard Docker setup | **Manual** |
| Want full control | **Manual** |

**Pro Tip:** Even if you need customization, start with the automatic generator to get a
buildable base, then modify the generated files!

---

## 📖 What You'll Create

Both guides help you create:

- **VM Image (QCOW2)** - Base OS with Docker Engine CE installed at build time.
  Default `ubuntu2204min`; set `BASE_OS` in the `.env` to one of `ubuntu2204min`,
  `ubuntu2204`, `ubuntu2404min`, `ubuntu2404`, `debian12`, `debian11`, `alma8`,
  `alma9`, `rocky8`, `rocky9`, `opensuse15`
- **Docker Container** - Your image, pulled at build time and baked into the qcow2
- **Automatic Startup** - Container started on boot with hardening flags:
  `--security-opt=no-new-privileges --cap-drop=ALL --cap-add=CHOWN,SETUID,SETGID,NET_BIND_SERVICE --pids-limit=512 --memory=1g`
- **SSH Access** - **Key-only.** The key is injected from the OpenNebula context variable
  `SSH_PUBLIC_KEY`; the deployed VM has **no password login** (root's password is locked and
  sshd is configured with `PasswordAuthentication no` / `PermitRootLogin prohibit-password`).
  The `opennebula` password is only the Packer communicator credential on the transient,
  localhost-bound build VM and never reaches the shipped image.
- **Console Access** - Auto-login to root on tty1 and on the serial console
- **OpenNebula Context** - Runtime configuration via `ONEAPP_CONTAINER_NAME`,
  `ONEAPP_CONTAINER_PORTS`, `ONEAPP_CONTAINER_ENV` and `ONEAPP_CONTAINER_VOLUMES`.
  Environment variables may hold secrets, so they are supplied at instantiation and are
  never baked into the image. Any hand-written VM template must pass these four through in
  its `CONTEXT` section.
- **VNC Access** - Graphical console via OpenNebula Sunstone

---

## 🚀 Quick Comparison

| Feature | Automatic | Manual |
|---------|-----------|--------|
| **Time to create** | Seconds | 30-45 minutes |
| **Difficulty** | Easy | Moderate |
| **Customization** | Limited | Full |
| **Learning curve** | Low | Medium |
| **Best for** | Standard containers | Custom requirements |
| **Files generated** | All files, including the packer dir and Makefile.config entry | You create all files |
| **Examples included** | Yes (4 working: nginx, postgres, redis, nodered) | Template provided |
| **Build integration** | Yes | You must register the appliance yourself |

---

## 📦 Example Appliances

The four `.env` files shipped in `docs/automatic-appliance-tutorial/examples/` have all been
built and booted:

| Example | `DOCKER_IMAGE` |
|---------|----------------|
| `nginx.env` | `nginx:alpine` |
| `postgres.env` | `postgres:15` |
| `redis.env` | `redis:alpine` |
| `nodered.env` | `nodered/node-red:5.0.1` |

The same approach works for other containerized software — web servers, databases,
development tools, monitoring stacks, automation platforms — subject to two rules the
generator enforces:

- **Pin the image.** `:latest` and untagged images are rejected; use a fixed tag or a digest.
- **No Docker socket mounts.** Mounting `/var/run/docker.sock` into the container is rejected
  as a container-escape vector.

> **Volumes:** when the appliance creates a *new* host directory for a volume mount, it chowns
> that directory to the UID/GID the container image runs as, which is what makes volumes work
> for images running unprivileged. A pre-existing host directory is never touched. Do not mount
> empty host directories over paths the image ships content in (that is why `examples/nginx.env`
> sets `DEFAULT_VOLUMES=""` — mounting over `/etc/nginx/conf.d` removed `default.conf` and nginx
> served nothing).

---

## ✅ End-to-end example

The full sequence, from a clean Linux host to a booting appliance image:

```bash
# 1. Clone the repository AND initialise the one-apps submodule (without this,
#    apps-code/community-apps/packer/build.sh is a dangling symlink and every build fails)
git clone https://github.com/OpenNebula/marketplace-community.git
cd marketplace-community
git submodule update --init --recursive

# 2. Install the build prerequisites (Ubuntu/Debian).
#    Full authoritative list: https://github.com/OpenNebula/one-apps/wiki/tool_reqs
sudo apt update
sudo apt install -y make ruby rpm rsync genisoimage cloud-utils cloud-image-utils \
                    qemu-utils qemu-system-x86 libguestfs-tools
sudo gem install --no-document backports fpm

#    Packer >= 1.9.4 is NOT in the Ubuntu archive - install HashiCorp's package:
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer

# 3. Build the base OS image ONCE (~2.5 minutes). Every appliance is built on top of it,
#    and 'make <name>' never builds it for you.
cd apps-code/one-apps
sudo make ubuntu2204min          # -> apps-code/one-apps/export/ubuntu2204min.qcow2
cd ../..

# 4. Generate the appliance from its .env description
cd docs/automatic-appliance-tutorial
sudo ./generate-docker-appliance.sh examples/nginx.env --no-build
cd ../..

# 5. Build the appliance image (~2 minutes)
cd apps-code/community-apps
sudo make nginx                  # -> apps-code/community-apps/export/nginx.qcow2
```

---

## 📚 Additional Resources

- [OpenNebula Documentation](https://docs.opennebula.io/)
- [one-apps build requirements](https://github.com/OpenNebula/one-apps/wiki/tool_reqs)
- [OpenNebula Marketplace](https://marketplace.opennebula.io/)
- [Docker Hub](https://hub.docker.com/)
- [Packer Documentation](https://www.packer.io/docs)
- [OpenNebula Community Forum](https://forum.opennebula.io/)
