#!/usr/bin/env bash
set -euo pipefail

echo -e "\e[92mVerifying Proxmox Cloud-Init networking...\e[0m" > /dev/console

PRIMARY_NIC="$(ip -4 route show default | awk 'NR == 1 {print $5}')"
if [ -z "${PRIMARY_NIC}" ]; then
  echo "No default IPv4 interface was configured by Proxmox Cloud-Init." >&2
  exit 1
fi

CONFIGURED_IP="$(ip -4 -o address show dev "${PRIMARY_NIC}" scope global | awk 'NR == 1 {split($4, value, "/"); print value[1]}')"
if [ "${CONFIGURED_IP}" != "${IP_ADDRESS}" ]; then
  echo "Cloud-Init configured ${CONFIGURED_IP:-no IPv4 address}, expected ${IP_ADDRESS}." >&2
  exit 1
fi

hostnamectl set-hostname "${HOSTNAME}"
sed -i '/# VIS appliance$/d' /etc/hosts
printf '%s %s %s # VIS appliance\n' "${IP_ADDRESS}" "${HOSTNAME}" "${HOSTNAME%%.*}" >> /etc/hosts

mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/vis.conf <<EOF
[Resolve]
DNS=${DNS_SERVERS}
Domains=${DNS_DOMAIN}
DNSStubListener=no
EOF
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved.service || true

mkdir -p /etc/systemd
if [ ! -f /etc/systemd/timesyncd.conf ]; then
  cat > /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=${NTP_SERVER}
EOF
else
  sed -i "s/^#\?NTP=.*/NTP=${NTP_SERVER}/" /etc/systemd/timesyncd.conf
  grep -q '^NTP=' /etc/systemd/timesyncd.conf || printf 'NTP=%s\n' "${NTP_SERVER}" >> /etc/systemd/timesyncd.conf
fi
systemctl restart systemd-timesyncd.service || true
