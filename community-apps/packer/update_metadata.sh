#!/bin/bash
LOGFILE=packer/update_metadata.log
APP_NAME=${1}                                   # e.g. debian
APP_VER=${2}                                    # e.g. 11
if [ -n "${APP_VER}" ]; then
    APP=${APP_NAME}${APP_VER}                   # e.g. debian11
else
    APP=${APP_NAME}
fi               
ORIGIN=${3}                                     # e.g. export/debian11-6.6.1-1.qcow2
DESTINATION=${DIR_APPLIANCES}/${APP}.qcow2      # e.g. /var/lib/one/6gsandbox-marketplace/ueransim326.qcow2
if [ -f "${DESTINATION}" ]; then
    mkdir ${DIR_APPLIANCES}/backup/
    BACKUP=${DIR_APPLIANCES}/backup/${APP}-$(stat -c %y "${DESTINATION}" | awk '{print $1}' | sed 's/-//g').qcow2   # e.g. /var/lib/one/6gsandbox-marketplace/backup/ueransim326.24-04-24.qcow2
else
    BACKUP=None
fi
METADATA=${DIR_METADATA}/${APP}.yaml             # e.g. /opt/marketplace/appliances/all/tnlcm0.yaml


# Verify if yq is installed, and install it
if ! command -v yq &> /dev/null
then
    echo "------------------SETUP--------------------------" >> ${LOGFILE}
    echo "Command yq is not present in the system. Installing" >> ${LOGFILE}
    sudo apt-get update && sudo apt-get install -y wget
    sudo wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64 -O /usr/bin/yq
    sudo chmod +x /usr/bin/yq
    echo "Command yq installed successfully" >> ${LOGFILE}
fi

echo "------------------New build--------------------------" >> ${LOGFILE}
echo APP_NAME=$–APP_NAME} >> ${LOGFILE}
echo APP_VER=${APP_VER} >> ${LOGFILE}
echo APP=${APP} >> ${LOGFILE}
echo ORIGIN=${ORIGIN} >> ${LOGFILE}
echo VERSION=${VERSION} >> ${LOGFILE}
echo DESTINATION=${DESTINATION} >> ${LOGFILE}
echo BACKUP=${BACKUP} >> ${LOGFILE}
echo METADATA=${METADATA} >> ${LOGFILE}

if [ -f "${DESTINATION}" ]; then
    mv "${DESTINATION}" "${BACKUP}"
fi
mv ${ORIGIN} ${DESTINATION}

# Calculate the values to update the appliance metadata
if [ -n "${APP_VER}" ]; then
    VERSION=${APP_VER}-$(date +"%Y%m%d-%H%M")         # e.g. 11-290424-1016
else
    VERSION=${APP_VER}                                # e.g. 290424-1016
fi   
TIMESTAMP="$(stat -c %W "${DESTINATION}")"
SIZE="$(qemu-img info "${DESTINATION}" | awk '/virtual size:/ {print $5}' | sed 's/[^0-9]*//g')"
MD5="$(md5sum "${DESTINATION}" | cut -d' ' -f1)"
SHA256="$(sha256sum "${DESTINATION}" | cut -d' ' -f1)"

echo TIMESTAMP=${TIMESTAMP} >> ${LOGFILE}
echo SIZE=${SIZE} >> ${LOGFILE}
echo MD5=${MD5} >> ${LOGFILE}
echo SHA256=${SHA256} >> ${LOGFILE}

cat "${METADATA}" | yq ".version = \"${VERSION}\"" | sponge "${METADATA}"
cat "${METADATA}" | yq ".creation_time = \"${TIMESTAMP}\"" | sponge "${METADATA}"
cat "${METADATA}" | yq ".images[0].size = \"${SIZE}\"" | sponge "${METADATA}"
cat "${METADATA}" | yq ".images[0].checksum.md5 = \"${MD5}\"" | sponge "${METADATA}"
cat "${METADATA}" | yq ".images[0].checksum.sha256 = \"${SHA256}\"" | sponge "${METADATA}"

sleep 10
systemctl restart appmarket-simple.service