#!/usr/bin/env bash
set -euxo pipefail

sudo install -d -o root -g root -m 0755 /root/setup /etc/vis /var/lib/vis
sudo install -o root -g root -m 0755 /tmp/setup.sh /root/setup/setup.sh
sudo install -o root -g root -m 0755 /tmp/setup-01-os.sh /root/setup/setup-01-os.sh
sudo install -o root -g root -m 0755 /tmp/setup-02-network.sh /root/setup/setup-02-network.sh
sudo install -o root -g root -m 0755 /tmp/setup-03-vis.sh /root/setup/setup-03-vis.sh

sudo tee /etc/systemd/system/vis-firstboot.service >/dev/null <<'EOF'
[Unit]
Description=VIS first-boot Proxmox Cloud-Init customization
After=cloud-final.service network-online.target qemu-guest-agent.service
Wants=cloud-final.service network-online.target qemu-guest-agent.service
ConditionPathExists=!/var/lib/vis/firstboot.complete

[Service]
Type=oneshot
ExecStart=/root/setup/setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vis-firstboot.service
