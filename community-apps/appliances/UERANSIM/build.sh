#!/usr/bin/env bash

set -o errexit -o pipefail
export DEBIAN_FRONTEND=noninteractive

REPO_URL="https://github.com/aligungr/UERANSIM"
REQUIRED_PACKAGES=("make" "gcc" "g++" "cmake" "curl" "libsctp-dev" "lksctp-tools" "iproute2")
REPOSITORY_PATH="appliances/UERANSIM/.repository"
FILES_PATH="appliances/UERANSIM/.files"

cleanup(){
  echo ""
  echo "ERROR: Something unexpected happened during the binary build script."
  exit 1
}
trap cleanup ERR


echo "Clone or update the UERANSIM repository"
if [ ! -d "${REPOSITORY_PATH}/.git" ]; then
    echo "Cloning UERANSIM at ${REPOSITORY_PATH}/ ..."
    rm -f "${REPOSITORY_PATH}/.placeholder"
    git clone "${REPO_URL}" "${REPOSITORY_PATH}/"
else
    echo "Pulling latest changes from origin to local..."
    cd "${REPOSITORY_PATH}/"
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
cd "${REPOSITORY_PATH}/"
make -j
chmod +x build/nr-*
cd - > /dev/null


echo "Copy files into previously existing directories"
rm -f "${FILES_PATH}/build/.placeholder"
cp -r "${REPOSITORY_PATH}/build/" "${FILES_PATH}/build"
rm -f "${FILES_PATH}/config/.placeholder"
cp -r "${REPOSITORY_PATH}/config/" "${FILES_PATH}/config"
