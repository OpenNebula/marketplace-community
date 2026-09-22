#!/usr/bin/env bash
# Adds Slurm accounting (slurmdbd on MariaDB) to a OneSlurm controller. Run as root there.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq slurmdbd mariadb-server >/dev/null
systemctl enable --now mariadb >/dev/null
DBPASS="$(openssl rand -hex 12)"
mysql -e "CREATE DATABASE IF NOT EXISTS slurm_acct_db; CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY '${DBPASS}'; ALTER USER 'slurm'@'localhost' IDENTIFIED BY '${DBPASS}'; GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost'; FLUSH PRIVILEGES;"
cat > /etc/slurm/slurmdbd.conf <<CONF
AuthType=auth/munge
DbdHost=localhost
SlurmUser=slurm
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageHost=localhost
StorageUser=slurm
StoragePass=${DBPASS}
StorageLoc=slurm_acct_db
CONF
chown slurm:slurm /etc/slurm/slurmdbd.conf; chmod 600 /etc/slurm/slurmdbd.conf
install -d -o slurm -g slurm /var/log/slurm
systemctl enable --now slurmdbd >/dev/null
sleep 3
# Point the controller at the database and register the cluster.
sed -i -E '/^AccountingStorageType=|^AccountingStorageHost=|^JobAcctGatherType=/d' /etc/slurm/slurm.conf
printf 'AccountingStorageType=accounting_storage/slurmdbd\nAccountingStorageHost=localhost\nJobAcctGatherType=jobacct_gather/linux\n' >> /etc/slurm/slurm.conf
cluster="$(sed -n 's/^ClusterName=//p' /etc/slurm/slurm.conf)"
sacctmgr -i add cluster "$cluster" >/dev/null 2>&1 || true
systemctl restart slurmctld
sleep 3
sacctmgr -n list cluster
systemctl is-active slurmdbd slurmctld mariadb
