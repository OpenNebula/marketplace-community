# Creating OpenNebula Appliances - Manual Method

**Complete control over appliance creation**

---

## 📖 Introduction

This guide shows you how to manually create OpenNebula appliances from Docker
containers. This approach gives you full control over every aspect of the
appliance and is recommended for advanced users or custom requirements.

If you just want a working appliance quickly, use the generator instead:
[Automatic Appliance Guide](AUTOMATIC_APPLIANCE_GUIDE.md).

**What you'll create:**
- A VM image (QCOW2 format) built on the one-apps Ubuntu 22.04 minimal base
- Docker installed at build time and your container started on first boot
- SSH key-only access (the public key is injected from OpenNebula context,
  `$USER[SSH_PUBLIC_KEY]`; there is no password login on the deployed VM)
- OpenNebula context integration for runtime configuration
  (`ONEAPP_CONTAINER_NAME`, `ONEAPP_CONTAINER_PORTS`, `ONEAPP_CONTAINER_ENV`,
  `ONEAPP_CONTAINER_VOLUMES`)

**Time required:** ~30-45 minutes to write the files, plus roughly 5 minutes of
build time (base OS image ~2.5 min, appliance image ~2 min).

Throughout this guide the example appliance is called `myapp`. Replace it with
your own lowercase name (letters, digits and hyphens only).

---

## ✅ Prerequisites

The build **must run on Linux, as root** (it uses `chroot`), on a host with KVM
(`/dev/kvm` present), at least 8 GB RAM and 40 GB free disk. macOS/BSD will not
work.

Full authoritative list: <https://github.com/OpenNebula/one-apps/wiki/tool_reqs>

```bash
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
```

Verify the host is ready:

```bash
packer --version        # must be >= 1.9.4
test -e /dev/kvm && echo "KVM OK"
```

`fpm` (ruby gem), `rpm` and `cloud-image-utils` (which provides `cloud-localds`)
are the three that are typically absent on a normal host and whose absence
breaks the base-image build with a confusing error.

You also need `git`, a text editor, and basic knowledge of bash and YAML.

---

## 📁 Step 1: Clone the Repository and Initialise Submodules

`apps-code/one-apps` is a **git submodule**. Without it,
`apps-code/community-apps/packer/build.sh` is a dangling symlink (it points at
`../../one-apps/packer/build.sh`) and `make <name>` fails on its first command.
`one-apps/appliances/service.sh`, `packer/common.pkr.hcl` and
`packer/postprocess.sh` are also missing without it.

```bash
# Clone the repository
git clone https://github.com/OpenNebula/marketplace-community.git
cd marketplace-community

# REQUIRED: pull in the apps-code/one-apps submodule
git submodule update --init --recursive

# Sanity check: this must resolve, not dangle
ls -l apps-code/community-apps/packer/build.sh
test -f apps-code/one-apps/appliances/service.sh && echo "submodule OK"

# Create the appliance directory (lowercase letters, digits and hyphens only)
mkdir -p appliances/myapp
cd appliances/myapp
```

---

## 📝 Step 2: Create the Appliance Metadata Files

Three separate files live in `appliances/myapp/`, and they are **not**
interchangeable. None of them configures Packer — the build is configured in
Step 5.

| File | Consumed by | Purpose |
|------|-------------|---------|
| `metadata.yaml` | `lib/community/app_handler.rb` | certification-test metadata (`:app:` / `:one:` / `:infra:`) |
| `context.yaml` | the test harness | default context values used by the tests |
| `<UUID>.yaml` | the marketplace | the published appliance listing |

### metadata.yaml

`app_handler.rb` reads `config[:one][:template][:NAME]`,
`config[:app][:context][:params]`, `config[:app][:context][:prefixed]` and
`config[:infra][:disk_format]`, so the leading-colon (Ruby symbol) keys below
are mandatory. Reference: `appliances/prowler/metadata.yaml`.

```bash
nano metadata.yaml
```

```yaml
---
:app:
  :name: myapp
  :type: service
  :os:
    :type: linux
    :base: ubuntu2204min
  :hypervisor: KVM
  :context:
    :prefixed: true
    :params:
      :ONEAPP_CONTAINER_NAME: 'myapp-container'
      :ONEAPP_CONTAINER_PORTS: '8080:8080'
      :ONEAPP_CONTAINER_ENV: ''
      :ONEAPP_CONTAINER_VOLUMES: ''

:one:
  :template:
    NAME: base
    TEMPLATE:
      ARCH: x86_64
      CONTEXT:
        NETWORK: 'YES'
        SET_HOSTNAME: "$NAME"
        SSH_PUBLIC_KEY: "$USER[SSH_PUBLIC_KEY]"
      CPU: '2'
      CPU_MODEL:
        MODEL: host-passthrough
      GRAPHICS:
        LISTEN: 0.0.0.0
        TYPE: vnc
      MEMORY: '2048'
      NIC:
        NETWORK: service
      NIC_DEFAULT:
        MODEL: virtio
  :datastore_name: default
  :timeout: '600'

:infra:
  :disk_format: qcow2
  :apps_path: /var/tmp
```

`:os: :base:` must be one of the base images one-apps can build (see Step 6b),
and it must match the `iso_url` you set in Step 5.

### context.yaml

```bash
nano context.yaml
```

```yaml
---
ONEAPP_CONTAINER_NAME: 'myapp-container'
ONEAPP_CONTAINER_PORTS: '8080:8080'
ONEAPP_CONTAINER_ENV: ''
ONEAPP_CONTAINER_VOLUMES: ''
```

### &lt;UUID&gt;.yaml — the marketplace listing

The filename must be a UUID. Without this file the appliance never appears in
the marketplace.

```bash
UUID=$(uuidgen)
nano "${UUID}.yaml"
```

```yaml
---
name: 'MyApp'
version: 1.0.0-1
one-apps_version: 7.0.0-0
publisher: 'Your Name'
publisher_email: 'your.email@domain.com'
description: |-
  MyApp running in a Docker container on Ubuntu 22.04 LTS (Minimal).

  **This appliance provides:**
  - Docker Engine CE pre-installed and configured
  - The MyApp container started automatically on first boot
  - SSH **key-only** access (the key comes from OpenNebula contextualization;
    there is no password login)
  - Container name, ports, environment and volumes configurable at instantiation
short_description: 'MyApp - Brief one-line description'
tags:
- docker
- myapp
- ubuntu
format: qcow2
creation_time: 1785151582
os-id: Ubuntu
os-release: '22.04'
os-arch: x86_64
hypervisor: KVM
opennebula_version: 6.10, 7.0
opennebula_template:
  context:
    network: 'YES'
    report_ready: 'YES'
    set_hostname: "$NAME"
    ssh_public_key: "$USER[SSH_PUBLIC_KEY]"
    oneapp_container_name: "$ONEAPP_CONTAINER_NAME"
    oneapp_container_ports: "$ONEAPP_CONTAINER_PORTS"
    oneapp_container_env: "$ONEAPP_CONTAINER_ENV"
    oneapp_container_volumes: "$ONEAPP_CONTAINER_VOLUMES"
  cpu: '2'
  vcpu: '2'
  memory: '2048'
  disk:
    image: $FILE[IMAGE_ID]
    image_uname: $USER[IMAGE_UNAME]
  graphics:
    listen: 0.0.0.0
    type: vnc
  os:
    arch: x86_64
  user_inputs:
    oneapp_container_name: 'M|text|Container name||myapp-container'
    oneapp_container_ports: 'M|text|Container ports (host:container)||8080:8080'
    oneapp_container_env: 'O|text|Environment variables (VAR=value,VAR2=value2)||'
    oneapp_container_volumes: 'O|text|Volume mounts (/host:/container)||'
  inputs_order: ONEAPP_CONTAINER_NAME,ONEAPP_CONTAINER_PORTS,ONEAPP_CONTAINER_ENV,ONEAPP_CONTAINER_VOLUMES
logo: logos/myapp.png
```

> Everything under `appliances/` is linted by `.github/workflows/yamllint.yml`
> with `.yamllint.yml`; keep lines free of trailing whitespace.

---

## 🔧 Step 3: Create appliance.sh

This is the main installation script. It is **sourced** by the one-apps service
manager at build and boot time, which then calls `service_install`,
`service_configure` and `service_bootstrap`. Use `appliances/prowler/appliance.sh`
as the reference implementation.

```bash
nano appliance.sh
```

### How this script is executed

Do **not** add a `case "$1" in install|configure|bootstrap` dispatcher and do not
run `appliance.sh` directly. The one-apps service manager
(`/etc/one-appliance/service`, copied in from
`apps-code/one-apps/appliances/service.sh`) **sources** this file and calls the
lifecycle functions itself:

```
/etc/one-appliance/service install     ->  sources appliance.sh, calls service_install
/etc/one-appliance/service configure   ->  sources appliance.sh, calls service_configure
/etc/one-appliance/service bootstrap   ->  sources appliance.sh, calls service_bootstrap
```

A dispatcher at the bottom of the file would run the stage twice (once while
being sourced, since positional parameters are inherited, and once from the
framework), and running the script standalone fails immediately because helpers
like `msg` only exist after the framework has sourced
`/etc/one-appliance/lib/common.sh`.

So the file must end after the last helper function — no `### Main execution`
block, no `case`, no `exit 1`.

**Template:**

```bash
#!/usr/bin/env bash

# MyApp Appliance Installation Script
# Docker Image: your-docker-image:tag

set -o errexit -o pipefail

# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_CONTAINER_NAME'     'configure'  'Docker container name'                    'O|text'
    'ONEAPP_CONTAINER_PORTS'    'configure'  'Docker container port mappings'           'O|text'
    'ONEAPP_CONTAINER_ENV'      'configure'  'Docker container environment variables'   'O|text'
    'ONEAPP_CONTAINER_VOLUMES'  'configure'  'Docker container volume mappings'         'O|text'
)

# Configuration - CUSTOMIZE THESE
# Always pin an immutable image tag. ':latest' is rejected: it makes the
# appliance unreproducible and silently changes what ships.
DOCKER_IMAGE="your-docker-image:1.2.3"
DEFAULT_CONTAINER_NAME="myapp-container"
DEFAULT_PORTS="8080:8080"
DEFAULT_ENV_VARS=""
# Leave empty unless the app really needs persistence. Mounting an empty host
# directory over a path the image already populates hides the image's own
# content and can break the application.
DEFAULT_VOLUMES=""
APP_NAME="MyApp"
APPLIANCE_NAME="myapp"

ONE_SERVICE_SETUP_DIR="/opt/one-appliance"   ### Install location. Required by bash helpers

### Appliance metadata ###############################################

ONE_SERVICE_NAME='MyApp'
ONE_SERVICE_VERSION='1.2.3'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='MyApp Docker Container Appliance'
ONE_SERVICE_DESCRIPTION='MyApp running in Docker container'
ONE_SERVICE_RECONFIGURABLE=true

### Appliance functions ##############################################

service_cleanup()
{
    :
}

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    # Update system
    msg info "Updating system packages"
    apt-get update
    apt-get upgrade -y

    # Install Docker
    msg info "Installing Docker"
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable Docker (it is started by systemd on the deployed VM)
    systemctl enable docker
    systemctl start docker

    # Pull the Docker image
    msg info "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"

    # NOTE: do NOT set a root password and do NOT enable password SSH here.
    #
    # The deployed appliance is SSH-KEY-ONLY. one-context injects
    # SSH_PUBLIC_KEY at instantiation; packer/myapp/81-configure-ssh.sh sets
    # `PasswordAuthentication no` / `PermitRootLogin without-password` before
    # the image is finalized, and packer/postprocess.sh runs
    # `virt-sysprep --root-password disabled`, which wipes any password set
    # here anyway. The password 'opennebula' belongs ONLY to the transient,
    # localhost-bound Packer build VM (see packer/myapp/gen_context) and must
    # never reach the shipped image.
    #
    # Root auto-login on tty1/ttyS0 is likewise omitted: anyone with VNC
    # access to the VM would get an unauthenticated root shell.
    #
    # Do not write /etc/motd either - the one-apps service manager owns it and
    # uses it to report the appliance status ("All set and ready to serve").

    msg info "${APP_NAME} installation completed"
}

service_configure()
{
    :
}

service_bootstrap()
{
    msg info "Starting ${APP_NAME} container"
    setup_app_container
}

setup_app_container()
{
    # Get configuration from context or use defaults
    local container_name="${ONEAPP_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    local container_ports="${ONEAPP_CONTAINER_PORTS:-$DEFAULT_PORTS}"
    local container_env="${ONEAPP_CONTAINER_ENV:-$DEFAULT_ENV_VARS}"
    local container_volumes="${ONEAPP_CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"

    msg info "Container configuration:"
    msg info "  Name: $container_name"
    msg info "  Ports: $container_ports"
    msg info "  Volumes: $container_volumes"
    # Do not log $container_env: it commonly carries secrets.

    # Stop and remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "Removing existing container: $container_name"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi

    # Parse port mappings
    local port_args=""
    if [ -n "$container_ports" ]; then
        IFS=',' read -ra PORT_ARRAY <<< "$container_ports"
        for port in "${PORT_ARRAY[@]}"; do
            port_args="$port_args -p $port"
        done
    fi

    # Parse environment variables
    local env_args=""
    if [ -n "$container_env" ]; then
        IFS=',' read -ra ENV_ARRAY <<< "$container_env"
        for env in "${ENV_ARRAY[@]}"; do
            env_args="$env_args -e $env"
        done
    fi

    # Parse volume mounts
    local volume_args=""
    if [ -n "$container_volumes" ]; then
        # The UID/GID the image runs as, so a freshly created host directory is
        # writable by an unprivileged container.
        local image_uid image_gid
        image_uid=$(docker image inspect -f '{{.Config.User}}' "$DOCKER_IMAGE" | cut -d: -f1)
        image_gid=$(docker image inspect -f '{{.Config.User}}' "$DOCKER_IMAGE" | cut -d: -f2)
        [ -n "$image_uid" ] || image_uid=0
        [ -n "$image_gid" ] || image_gid="$image_uid"

        IFS=',' read -ra VOL_ARRAY <<< "$container_volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            local host_path
            host_path=$(echo "$vol" | cut -d':' -f1)
            # Only touch directories we create ourselves; never chown a
            # pre-existing host directory.
            if [ ! -e "$host_path" ]; then
                mkdir -p "$host_path"
                chown -R "${image_uid}:${image_gid}" "$host_path" 2>/dev/null || true
            fi
            volume_args="$volume_args -v $vol"
        done
    fi

    # Start container
    msg info "Starting Docker container: $container_name"
    docker run -d --name "$container_name" --restart unless-stopped $port_args $env_args $volume_args "$DOCKER_IMAGE"

    # Wait for container to start
    sleep 5

    # Verify container is running
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "${APP_NAME} container started successfully"
        msg info "Container status:"
        docker ps --filter "name=${container_name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        msg error "${APP_NAME} container failed to start"
        msg error "Container logs:"
        docker logs "$container_name" 2>&1 | tail -20
        return 1
    fi
}
```

**Make it executable:**

```bash
chmod +x appliance.sh
```

---

## 📄 Step 4: Create Additional Files

### README.md

```bash
nano README.md
```

```markdown
# MyApp Appliance

MyApp description and features.

## Quick Start

1. Deploy the appliance from OpenNebula Marketplace
2. Access via SSH: `ssh root@<vm-ip>` — **key-only**; the key is injected by
   OpenNebula contextualization from `$USER[SSH_PUBLIC_KEY]`. There is no
   password login.
3. Access web interface: `http://<vm-ip>:8080`

## Configuration

Configure the container via OpenNebula context variables (set them at
instantiation, not in the image):

- `ONEAPP_CONTAINER_NAME` - Container name (default: myapp-container)
- `ONEAPP_CONTAINER_PORTS` - Port mappings (default: 8080:8080)
- `ONEAPP_CONTAINER_ENV` - Environment variables, comma-separated `VAR=value`
  (use this for secrets; they are never baked into the image)
- `ONEAPP_CONTAINER_VOLUMES` - Volume mappings, comma-separated
  `/host/path:/container/path`. Leave empty unless you really need
  persistence: mounting an empty host directory over a path the image already
  populates hides the image's own content and can break the application.

## Support

For issues, visit: https://github.com/OpenNebula/marketplace-community
```

### CHANGELOG.md

```bash
nano CHANGELOG.md
```

```markdown
# Changelog

## [1.0.0] - 2025-10-02

### Added
- Initial release
- Docker container started by service_bootstrap via one-context
- OpenNebula context integration (ONEAPP_CONTAINER_*)
- SSH key-only access
```

### tests.yaml (appliance root) and tests/

`lib/community/app_readiness.rb` loads `appliances/myapp/tests.yaml` — at the
appliance root, **not** inside `tests/` — and expects a YAML *sequence of rspec
filenames*, which it runs from `appliances/myapp/tests/`. A `tests:` mapping of
shell commands is not read by anything.

```bash
mkdir -p tests

cat > tests.yaml <<'EOF'
---
- 00-myapp_basic.rb
EOF

nano tests/00-myapp_basic.rb
```

```ruby
require_relative '../../../lib/community/app_handler'

describe 'Appliance Certification' do
    include_context('vm_handler')

    it 'docker service is running' do
        result = @info[:vm].ssh('systemctl is-active docker')
        expect(result.exitstatus).to eq(0)
        expect(result.stdout.strip).to eq('active')
    end

    it 'myapp container is up' do
        start_time = Time.now
        timeout = 240

        loop do
            result = @info[:vm].ssh("docker ps --filter name=myapp-container --format '{{.Status}}'")
            break if result.success? && result.stdout.include?('Up')
            raise "container not up within #{timeout}s" if Time.now - start_time > timeout
            sleep 5
        end
    end

    it 'one-apps reports the service as ready' do
        result = @info[:vm].ssh('cat /etc/motd')
        expect(result.stdout).to include('All set and ready to serve')
    end
end
```

Run them from the frontend, **as the `oneadmin` user**:

```bash
# rspec is not part of the OpenNebula gem set; install it once
sudo gem install --no-document rspec

# the qcow2 must be readable by oneadmin (oned runs as oneadmin), so publish it
# somewhere outside /root - :apps_path: in metadata.yaml points at /var/tmp
sudo cp apps-code/community-apps/export/myapp.qcow2 /var/tmp/ && sudo chmod 644 /var/tmp/myapp.qcow2

sudo -u oneadmin env IMAGES_URL=/var/tmp/ bash -c 'cd lib/community && mkdir -p results && ./app_readiness.rb myapp'
```

Three things bite here if you get them wrong:

- **Run as `oneadmin`, not root.** The harness reaches the VM with
  `ssh root@<vm-ip>`, and the only key the VM trusts is the one contextualization
  injected from `$USER[SSH_PUBLIC_KEY]` — oneadmin's. As root you get
  `Permission denied (publickey)` and every example fails with
  `reached timeout ... reachable?`.
- **`IMAGES_URL` must point at a directory `oneadmin` can read.** The harness
  creates the image from `${IMAGES_URL}myapp.qcow2`; a path under `/root` fails
  with `Cannot parse image SIZE: ... (Permission denied)`.
- **The harness needs a VM template named `base`.** `defaults.yaml` sets
  `:template: base`, and `app_handler.rb` instantiates it with `--disk <image>`
  and the context built from your `metadata.yaml` `:params:`. Create one with
  the CPU/memory/NIC/graphics your appliance needs before running the tests.

See `appliances/prowler/tests/00-prowler_basic.rb` for a full example. Do not
use the minitest `class X < Test` style — `Test` is not defined in this harness
and it fails with `NameError: uninitialized constant Test`. Make each check
retry: the VM answers SSH before the appliance has finished bootstrapping, so a
single-shot `expect(...)` on `systemctl is-active docker` is racy.

---

## 🏗️ Step 5: Create the Packer Build Definition

`make myapp` runs `apps-code/community-apps/packer/build.sh`, which does exactly this:

```
packer init packer/myapp
packer build -force \
  -var appliance_name=myapp -var version= \
  -var input_dir=packer/myapp -var output_dir=build/myapp \
  -var headless=true -var arch=x86_64 \
  packer/myapp
qemu-img convert -c -O qcow2 build/myapp/myapp export/myapp.qcow2
```

Three consequences you must respect:

* every `-var` above must be **declared** in the directory, or Packer aborts with
  `Undefined variable ... was set but was not declared`;
* the image must be written to `var.output_dir` (never a hardcoded path),
  because `build.sh` converts `build/myapp/myapp` into `export/myapp.qcow2`;
* `packer build` runs with the working directory set to
  `apps-code/community-apps`, so every `source`/`scripts` path in the HCL is
  relative to **that** directory — not to `packer/myapp/`.

The build does **not** install an OS from an ISO. It boots the prebuilt base
image produced by one-apps (`../one-apps/export/ubuntu2204min.qcow2`) as a disk
image and runs the one-apps appliance lifecycle inside it.

```bash
cd ../../apps-code/community-apps
mkdir -p packer/myapp
```

### common.pkr.hcl (symlink — required)

Declares the `arch` / `arch_vars` variables that `build.sh` passes and pins the
qemu plugin.

```bash
ln -sf ../../../one-apps/packer/common.pkr.hcl packer/myapp/common.pkr.hcl
```

### variables.pkr.hcl

`packer/build.sh` always passes `appliance_name`, `version`, `input_dir`,
`output_dir` and `headless` on the command line, so these variables **must** be
declared or the build stops with `Error: Undefined -var variable`.

```bash
nano packer/myapp/variables.pkr.hcl
```

```hcl
variable "appliance_name" {
  type = string
}

variable "version" {
  type = string
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type    = bool
  default = true
}
```

### gen_context (build-time context ISO)

`PASSWORD='opennebula'` here is the **Packer communicator credential for the
transient, localhost-bound build VM only** — identical to
`packer/example/gen_context`. It never reaches the exported image:
`81-configure-ssh.sh` re-disables password SSH during the build and
`packer/postprocess.sh` runs `virt-sysprep --root-password disabled`.

```bash
cat > packer/myapp/gen_context <<'GENEOF'
#!/bin/bash
set -eux -o pipefail

SCRIPT=$(cat <<'MAINEND'
rm -f /etc/ssh/sshd_config.d/*cloudimg*.conf
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
systemctl reload sshd || systemctl reload ssh || true
echo "nameserver 1.1.1.1" > /etc/resolv.conf
MAINEND
)

cat <<CTXEOF
ETH0_METHOD='dhcp'
NETWORK='YES'
SET_HOSTNAME='myapp'
PASSWORD='opennebula'
ETH0_MAC='00:11:22:33:44:55'
NETCFG_TYPE='netplan'
START_SCRIPT_BASE64="$(echo "$SCRIPT" | base64 -w0)"
CTXEOF
GENEOF
chmod +x packer/myapp/gen_context
```

> `NETCFG_TYPE` depends on the base OS: `netplan` for ubuntu2204*/ubuntu2404*,
> `interfaces` for debian11/debian12, `nm` for alma8/alma9/rocky8/rocky9,
> `scripts` for opensuse15.

### 81-configure-ssh.sh (re-hardens sshd before export)

```bash
cat > packer/myapp/81-configure-ssh.sh <<'SSHEOF'
#!/usr/bin/env bash
exec 1>&2
set -eux -o pipefail

sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/'  /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
sed -i 's/^#*UseDNS.*/UseDNS no/'                                 /etc/ssh/sshd_config
grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
grep -q '^PermitRootLogin'        /etc/ssh/sshd_config || echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config

sync
SSHEOF
chmod +x packer/myapp/81-configure-ssh.sh
```

### 82-configure-context.sh

```bash
cat > packer/myapp/82-configure-context.sh <<'CTXSHEOF'
#!/usr/bin/env bash
exec 1>&2
set -eux -o pipefail

mv /etc/one-appliance/net-90-service-appliance /etc/one-context.d/
mv /etc/one-appliance/net-99-report-ready      /etc/one-context.d/

chown root:root /etc/one-context.d/*
chmod u=rwx,go=rx /etc/one-context.d/*

# NetworkManager netplan files written during the build conflict with
# one-context's 50-one-context.yaml at runtime and stop eth0 getting an IP.
rm -f /etc/netplan/90-NM-*.yaml
rm -f /etc/netplan/50-one-context.yaml

sync
CTXSHEOF
chmod +x packer/myapp/82-configure-context.sh
```

### myapp.pkr.hcl

This is the build definition `make myapp` runs. The file name must match the
appliance name, because `packer/build.sh` loads every `*.pkr.hcl` in
`packer/myapp/`.

```bash
nano packer/myapp/myapp.pkr.hcl
```

```hcl
source "null" "null" { communicator = "none" }

# Build the build-time context ISO first
build {
  sources = ["source.null.null"]

  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.input_dir}/context",
      "${var.input_dir}/gen_context > ${var.input_dir}/context/context.sh",
      "mkisofs -o ${var.input_dir}/${var.appliance_name}-context.iso -V CONTEXT -J -R ${var.input_dir}/context",
    ]
  }
}

source "qemu" "myapp" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  # Base image built by: cd apps-code/one-apps && sudo make ubuntu2204min
  iso_url      = "../one-apps/export/ubuntu2204min.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "8000"

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-serial", "stdio"],
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    # MAC addr must match ETH0_MAC from the context ISO
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = var.appliance_name
}

build {
  sources = ["source.qemu.myapp"]

  # Revert the insecure SSH settings enabled by the build context
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  # Bash helpers: this is where msg(), gen_password() etc. come from
  provisioner "file" {
    sources = [
      "../../lib/common.sh",
      "../../lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  # The appliance service manager that sources your appliance.sh
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  # Your logic. It MUST be named appliance.sh
  provisioner "file" {
    sources     = ["../../appliances/myapp/appliance.sh"]
    destination = "/etc/one-appliance/service.d/"
  }

  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  # Run the install stage, then lock the root account password as the final
  # in-guest step so the shipped image is SSH-key / context only and the
  # build-time password cannot be used for console login.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install", "passwd -l root", "sync"]
  }

  # virt-sysprep: strip machine-id, disable the root password, sparsify
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["packer/postprocess.sh"]
  }
}
```

### .gitignore — transient artifacts only

Do **not** ignore `myapp.pkr.hcl` or `gen_context`; they are the build
definition and must be in your PR, otherwise nobody can rebuild your appliance.

```bash
cat > packer/myapp/.gitignore <<'EOF'
context/
context.sh
*-context.iso
EOF
```

---

## 🎨 Step 6: Add Logo

Create a 256x256 PNG logo and drop it in `logos/`:

```bash
# from apps-code/community-apps, go back to the repository root
cd ../..
# Add your myapp.png file here (256x256 pixels)
cp /path/to/your-logo.png logos/myapp.png
```

Reference it from the marketplace listing as `logo: logos/myapp.png`.

The remaining steps all start from the repository root.

---

## 🧱 Step 6b: Build the one-apps Base Image (required, once per base OS)

The appliance build starts from a prebuilt base image at
`apps-code/one-apps/export/<BASE_OS>.qcow2`. **`make <name>` in
`community-apps` never builds it for you** — if the file is missing, the build
fails immediately.

```bash
cd apps-code/one-apps
sudo make ubuntu2204min          # ~2.5 minutes
ls -l export/ubuntu2204min.qcow2 # must exist before Step 7
cd ../..
```

This step also builds the one-context packages
(`context-linux/generate-all.sh`), which is why the `fpm` ruby gem and `rpm` are
in the prerequisites. Docker is *not* required for it.

Supported base images (this is the value you must also use for `iso_url` in
Step 5 and for `:os: :base:` in `metadata.yaml`):

```
ubuntu2204min  ubuntu2204  ubuntu2404min  ubuntu2404
debian12       debian11    alma8          alma9
rocky8         rocky9      opensuse15
```

---

## 🔨 Step 7: Register the Service and Build

`make <name>` only works for names listed in `SERVICES` in
`apps-code/community-apps/Makefile.config`. The `Makefile` derives every target
from that list (`$(SERVICES): %: packer-%`), so an unregistered name fails with
`make: *** No rule to make target 'myapp'.  Stop.`

### 7a. Register the appliance

```bash
cd apps-code/community-apps

# Append 'myapp' to the SERVICES list (idempotent)
grep -qE '^SERVICES :=.*( |:=)myapp( |$)' Makefile.config \
  || sed -i 's/^\(SERVICES :=.*\)$/\1 myapp/' Makefile.config

grep '^SERVICES' Makefile.config
```

### 7b. Build

Still in `apps-code/community-apps`:

```bash
sudo make myapp
```

`make myapp` runs `packer/build.sh 'myapp' '' export/myapp.qcow2`, which does
`packer init packer/myapp`, `packer build` with the `appliance_name`,
`version`, `input_dir`, `output_dir`, `headless` and `arch` variables, and then
`qemu-img convert -c -O qcow2 build/myapp/myapp export/myapp.qcow2`.

**Build time:** ~2 minutes once the base image exists.

**Output:** `apps-code/community-apps/export/myapp.qcow2`

`Makefile.config` is part of the contribution — commit it with the rest (Step 10).

---

## 🧪 Step 8: Test Locally

The exported image is a **contextualized cloud image**, not a standalone VM: it
has no password (`virt-sysprep --root-password disabled` runs at the end of the
build), no baked-in SSH key, and its `service_configure` / `service_bootstrap`
stages are triggered by one-context. Booting it with plain `qemu-system-x86_64`
and no CONTEXT CD-ROM leaves the container un-started and gives you no way in.

Attach a context ISO instead:

```bash
cd export        # apps-code/community-apps/export

mkdir -p /tmp/ctx
cat > /tmp/ctx/context.sh <<EOF
NETWORK='YES'
ETH0_METHOD='dhcp'
SET_HOSTNAME='myapp'
SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
ONEAPP_CONTAINER_NAME='myapp-container'
ONEAPP_CONTAINER_PORTS='8080:8080'
ONEAPP_CONTAINER_ENV=''
ONEAPP_CONTAINER_VOLUMES=''
EOF
genisoimage -o /tmp/myapp-context.iso -V CONTEXT -J -R /tmp/ctx

cp myapp.qcow2 /tmp/myapp-test.qcow2
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 2048 -smp 2 \
  -drive file=/tmp/myapp-test.qcow2,format=qcow2,if=virtio \
  -cdrom /tmp/myapp-context.iso \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

Then verify from another terminal (key authentication only — there is no
password login):

```bash
ssh -p 2222 root@127.0.0.1 'docker ps'
ssh -p 2222 root@127.0.0.1 'cat /etc/motd'   # expect "All set and ready to serve"
ssh -p 2222 root@127.0.0.1 'docker logs myapp-container'
curl -sI http://127.0.0.1:8080
```

---

## 🚀 Step 9: Deploy to OpenNebula

### Upload Image

```bash
# Copy to OpenNebula frontend
scp myapp.qcow2 root@opennebula-frontend:/var/tmp/

# SSH to frontend
ssh root@opennebula-frontend

# Create image in OpenNebula
oneimage create --name "MyApp" \
  --path /var/tmp/myapp.qcow2 \
  --type OS \
  --datastore default \
  --description "MyApp Docker Container Appliance"
```

### Create VM Template

`USER_INPUTS` only *collects* values into the template. They reach the guest
only if `CONTEXT` references them with `$VAR` — omitting those lines is why
operator input silently never arrives in the appliance.

```bash
cat > myapp-template.txt << 'EOF'
NAME = "MyApp"
CPU = "2"
VCPU = "2"
MEMORY = "2048"

DISK = [
  IMAGE = "MyApp"
]

NIC = [
  NETWORK = "default",
  NETWORK_UNAME = "oneadmin"
]

GRAPHICS = [
  LISTEN = "0.0.0.0",
  TYPE = "VNC"
]

CONTEXT = [
  NETWORK = "YES",
  REPORT_READY = "YES",
  SET_HOSTNAME = "$NAME",
  SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]",
  ONEAPP_CONTAINER_NAME = "$ONEAPP_CONTAINER_NAME",
  ONEAPP_CONTAINER_PORTS = "$ONEAPP_CONTAINER_PORTS",
  ONEAPP_CONTAINER_ENV = "$ONEAPP_CONTAINER_ENV",
  ONEAPP_CONTAINER_VOLUMES = "$ONEAPP_CONTAINER_VOLUMES"
]

USER_INPUTS = [
  ONEAPP_CONTAINER_NAME = "M|text|Container name||myapp-container",
  ONEAPP_CONTAINER_PORTS = "M|text|Port mappings (host:container)||8080:8080",
  ONEAPP_CONTAINER_ENV = "O|text|Environment variables (VAR=value,VAR2=value2)||",
  ONEAPP_CONTAINER_VOLUMES = "O|text|Volume mappings (/host:/container)||"
]

INPUTS_ORDER = "ONEAPP_CONTAINER_NAME,ONEAPP_CONTAINER_PORTS,ONEAPP_CONTAINER_ENV,ONEAPP_CONTAINER_VOLUMES"
EOF

onetemplate create myapp-template.txt
```

> Container environment variables often carry secrets, which is why they are
> supplied at instantiation through `ONEAPP_CONTAINER_ENV` rather than baked
> into the image.

### Instantiate VM

```bash
onetemplate instantiate "MyApp" --name "myapp-test"

# Check status
onevm list

# Get IP address
onevm show myapp-test | grep ETH0_IP
```

### Test Access

```bash
# SSH access (key-only: the key is injected by OpenNebula contextualization
# from $USER[SSH_PUBLIC_KEY]; there is NO password login on the deployed VM)
ssh root@<vm-ip>

# Check the one-apps lifecycle finished
cat /etc/motd            # expect "All set and ready to serve"

# Check container
docker ps

# Check logs
docker logs myapp-container
```

---

## 📤 Step 10: Submit to Marketplace

### Create Fork and Branch

```bash
# Fork the repository on GitHub first
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/marketplace-community.git
cd marketplace-community
git submodule update --init --recursive

# Create feature branch
git checkout -b feature/add-myapp-appliance
```

### Add Your Files

```bash
git add appliances/myapp/
git add apps-code/community-apps/packer/myapp/
# REQUIRED: without the SERVICES entry nobody can run `make myapp`
git add apps-code/community-apps/Makefile.config
git add logos/myapp.png

# Sanity check: the build definition must actually be in the commit
git status --short
git check-ignore -v apps-code/community-apps/packer/myapp/myapp.pkr.hcl \
  && echo "ERROR: myapp.pkr.hcl is gitignored - your PR would not build"

git commit -m "Add MyApp appliance

- Docker container started by service_bootstrap via one-context
- OpenNebula context integration (ONEAPP_CONTAINER_*)
- SSH key-only access
- Web interface on port 8080"
```

### Push and Create PR

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

- Docker container started on first boot by `service_bootstrap`
- OpenNebula context integration
- Configurable via context variables:
  - Container name
  - Port mappings
  - Environment variables (use this for secrets)
  - Volume mappings

## Testing

- ✅ Built successfully with Packer (`sudo make myapp`)
- ✅ Deployed to OpenNebula
- ✅ Container starts automatically
- ✅ SSH key access works (key-only; no password login, root password disabled by virt-sysprep)
- ✅ `/etc/motd` reports "All set and ready to serve"
- ✅ Application accessible on configured ports

## Files Added

- `appliances/myapp/` - Appliance definition, metadata, listing and tests
- `apps-code/community-apps/packer/myapp/` - Packer build configuration
- `apps-code/community-apps/Makefile.config` - `myapp` added to `SERVICES`
- `logos/myapp.png` - Appliance logo

## Checklist

- [x] Appliance builds successfully
- [x] Appliance tested on OpenNebula
- [x] Documentation included (README.md)
- [x] Logo added (256x256 PNG)
- [x] Follows the one-apps service framework structure (see `appliances/prowler/` and `apps-code/community-apps/packer/prowler/`)
- [x] Registered in `apps-code/community-apps/Makefile.config` SERVICES
- [x] Docker image pinned to an immutable tag (not `:latest`)
- [x] No sensitive information in files
```

---

## 🐛 Troubleshooting

**Problem:** `make: *** No rule to make target 'myapp'. Stop.`
**Solution:** `myapp` is not in `SERVICES` in
`apps-code/community-apps/Makefile.config` (Step 7a).

**Problem:** `packer/build.sh: No such file or directory`
**Solution:** The `apps-code/one-apps` submodule is not initialised. Run
`git submodule update --init --recursive` (Step 1).

**Problem:** Packer aborts with `Undefined variable ... was set but was not declared`
**Solution:** `variables.pkr.hcl` or the `common.pkr.hcl` symlink is missing
from `packer/myapp/` (Step 5).

**Problem:** The build fails immediately looking for
`../one-apps/export/ubuntu2204min.qcow2`
**Solution:** Build the base image first: `cd apps-code/one-apps && sudo make ubuntu2204min`
(Step 6b). `make <name>` never builds it for you.

**Problem:** Container doesn't start
**Solution:** Check Docker logs on the VM: `docker logs <container-name>`, and
the appliance log with `journalctl -u one-context`.

**Problem:** `Permission denied (publickey)` when SSHing to the deployed VM
**Solution:** Expected if no key was injected. The appliance is key-only —
make sure `SSH_PUBLIC_KEY` is in the template `CONTEXT` and that your user has
`SSH_PUBLIC_KEY` set (`oneuser update <user>`).

**Problem:** Operator-supplied `ONEAPP_CONTAINER_*` values are ignored
**Solution:** The template's `CONTEXT` section is missing the
`ONEAPP_CONTAINER_* = "$ONEAPP_CONTAINER_*"` lines. `USER_INPUTS` alone does
not reach the guest (Step 9).

**Problem:** The app serves nothing after mounting a volume
**Solution:** You mounted an empty host directory over a path the image already
populates. Leave `ONEAPP_CONTAINER_VOLUMES` empty unless you need persistence.

---

## 💡 Tips

- **Follow the pattern** - Use `appliances/prowler/` plus
  `apps-code/community-apps/packer/prowler/` as the reference for a Docker-based
  community appliance
- **Never run appliance.sh directly** - it is sourced by
  `/etc/one-appliance/service`, which calls the lifecycle functions
- **Pin image tags** - `:latest` is rejected; it makes the appliance
  unreproducible
- **Never mount the Docker socket** - `/var/run/docker.sock` is a container
  escape vector and is rejected
- **Use logging** - Add `msg info` statements for debugging, but never log
  `ONEAPP_CONTAINER_ENV`, it can carry secrets
- **Volume permissions** - only chown a host directory you created yourself;
  never touch a pre-existing one
- **Keep it simple** - Start with minimal features, add incrementally

---

## 📖 Additional Resources

- [Automatic Appliance Guide](AUTOMATIC_APPLIANCE_GUIDE.md) - For quick generation
- [one-apps build requirements](https://github.com/OpenNebula/one-apps/wiki/tool_reqs)
- [OpenNebula Documentation](https://docs.opennebula.io/)
- [Docker Hub](https://hub.docker.com/)
- [Packer Documentation](https://www.packer.io/docs)
- [OpenNebula Marketplace](https://marketplace.opennebula.io/)
