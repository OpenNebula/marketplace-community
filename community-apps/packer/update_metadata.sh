#!/bin/bash
LOGFILE=packer/update_metadata.log
DISTRO_NAME=$1                                    # e.g. debian
DISTRO_VER=$2                                     # e.g. 11
DISTRO=${DISTRO_NAME}${DISTRO_VER}                # e.g. debian11
ORG=$3                                            # e.g. export/debian11-6.6.1-1.qcow2
VERSION=$DISTRO_VER-$(date +"%Y%m%d-%H%M")        # e.g. 11-290424-1016
DST=$DIR_APPLIANCES/$DISTRO.qcow2                 # e.g. /var/lib/one/6gsandbox-marketplace/ueransim326.qcow2
if [ -f "$DST" ]; then
    mkdir ${DIR_APPLIANCES}/backup/
    BKUP=${DIR_APPLIANCES}/backup/${DISTRO}-$(stat -c %y "$DST" | awk '{print $1}' | sed 's/-//g').qcow2   # e.g. /var/lib/one/6gsandbox-marketplace/backup/ueransim326.24-04-24.qcow2
else
    BKUP=None
fi
METADATA=$DIR_METADATA/$DISTRO.yaml               # e.g. /opt/marketplace/appliances/all/tnlcm0.yaml

# Verify if yq is installed, and instell it
if ! command -v yq &> /dev/null
then
    echo "------------------SETUP--------------------------" >> $LOGFILE
    echo "Command yq is not present in the system. Installing" >> $LOGFILE
    sudo apt-get update && sudo apt-get install -y wget
    sudo wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64 -O /usr/bin/yq
    sudo chmod +x /usr/bin/yq
    echo "Command yq installed successfully" >> $LOGFILE
fi

echo "------------------New build--------------------------" >> $LOGFILE
echo DISTRO_NAME=$DISTRO_NAME >> $LOGFILE
echo DISTRO_VER=$DISTRO_VER >> $LOGFILE
echo DISTRO=$DISTRO >> $LOGFILE
echo ORG=$ORG >> $LOGFILE
echo VERSION=$VERSION >> $LOGFILE
echo DST=$DST >> $LOGFILE
echo BKUP=$BKUP >> $LOGFILE
echo METADATA=$METADATA >> $LOGFILE

if [ -f "$DST" ]; then
    mv "$DST" "$BKUP"
fi
mv $ORG $DST

# Calculate values to update the appliance metadata
TIMESTAMP="$(stat -c %W "$DST")"
SIZE="$(qemu-img info "$DST" | awk '/virtual size:/ {print $5}' | sed 's/[^0-9]*//g')"
MD5="$(md5sum "$DST" | cut -d' ' -f1)"
SHA256="$(sha256sum "$DST" | cut -d' ' -f1)"

echo TIMESTAMP=$TIMESTAMP >> $LOGFILE
echo SIZE=$SIZE >> $LOGFILE
echo MD5=$MD5 >> $LOGFILE
echo SHA256=$SHA256 >> $LOGFILE

cat "$METADATA" | yq ".version = \"$VERSION\"" | sponge "$METADATA"
cat "$METADATA" | yq ".creation_time = \"$TIMESTAMP\"" | sponge "$METADATA"
cat "$METADATA" | yq ".images[0].size = \"$SIZE\"" | sponge "$METADATA"
cat "$METADATA" | yq ".images[0].checksum.md5 = \"$MD5\"" | sponge "$METADATA"
cat "$METADATA" | yq ".images[0].checksum.sha256 = \"$SHA256\"" | sponge "$METADATA"

sleep 10
systemctl restart appmarket-simple.service