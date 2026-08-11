#!/usr/bin/env bash
set -euo pipefail

echo -e "\e[92mConfiguring the appliance OS...\e[0m" > /dev/console

systemctl enable --now qemu-guest-agent.service
systemctl enable --now ssh.service
rm -f /etc/sudoers.d/99-vis-packer

if [ "${OS_PASSWORD_ENABLED}" != "true" ]; then
  passwd -l visadmin >/dev/null 2>&1 || true
  echo 'visadmin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-visadmin-cloud
  chmod 0440 /etc/sudoers.d/90-visadmin-cloud
else
  rm -f /etc/sudoers.d/90-visadmin-cloud
fi

mkdir -p \
  /opt/vis/config \
  /opt/vis/data/dns \
  /opt/vis/data/registry \
  /opt/vis/data/sftp/backup \
  /opt/vis/data/depot \
  /opt/vis/data/identity \
  /opt/vis/data/time \
  /opt/vis/data/dhcp \
  /opt/vis/data/kms \
  /opt/vis/state
