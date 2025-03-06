#!/usr/bin/env bash

set -o errexit -o pipefail
export DEBIAN_FRONTEND=noninteractive

REPO_URL="https://github.com/aligungr/UERANSIM"
REQUIRED_PACKAGES=("make" "gcc" "g++" "cmake" "curl" "libsctp-dev" "lksctp-tools" "iproute2")
BUILD_PATH="appliances/UERANSIM/UERANSIM"

cleanup(){
  echo ""
  echo "ERROR: Something unexpected happened during the binary build script."
  exit 1
}
trap cleanup ERR


echo "Clone or update the UERANSIM repository"
if [ ! -d "${BUILD_PATH}/.git" ]; then
    echo "Cloning UERANSIM at ${BUILD_PATH}..."
    git clone "${REPO_URL}" "${BUILD_PATH}"
else
    echo "Pulling latest changes from origin to local..."
    cd "${BUILD_PATH}"
    git reset --hard HEAD
    git pull --rebase
    cd - > /dev/null
fi

echo "Install or update the required .deb packages"
apt-get update
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    apt-get install -y "${pkg}"
done

echo "Build UERANSIM binaries"
cd ${BUILD_PATH}
make -j
chmod +x build/nr-*
