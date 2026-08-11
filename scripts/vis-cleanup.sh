#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

echo '> Removing build-time appliance identity and secrets...'
sudo systemctl stop vis-web.service 2>/dev/null || true
sudo rm -f /opt/vis/state/vis.db /opt/vis/config/app-secret
sudo rm -f /etc/systemd/system/vis-web.service.d/firstboot-env.conf
sudo rm -f /var/lib/vis/firstboot.complete /etc/vis/firstboot.json

sudo passwd -l visadmin || true
sudo rm -f /home/visadmin/.ssh/authorized_keys
sudo rm -f /root/.ssh/authorized_keys
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
sudo cloud-init clean --logs --seed

echo '> Clearing apt caches, temporary files, and transient logs...'
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/* /tmp/vis /tmp/vis-optional-files
sudo truncate -s 0 /var/log/wtmp || true
sudo find /var/log -type f -exec truncate -s 0 {} \; || true
sudo rm -rf /var/log/journal/* /var/lib/dhcp/*
sudo fstrim -av || true
sudo sync

# Replace the broad build-only sudo rule with the single command Packer needs
# after this provisioner returns. First boot removes the narrow rule.
echo 'visadmin ALL=(root) NOPASSWD: /usr/sbin/shutdown -P now' | sudo tee /etc/sudoers.d/99-vis-packer >/dev/null
sudo chmod 0440 /etc/sudoers.d/99-vis-packer

echo '> Proxmox template sealing complete.'
