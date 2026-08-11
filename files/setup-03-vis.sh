#!/usr/bin/env bash
set -euo pipefail

echo -e "\e[92mInitializing VIS application state...\e[0m" > /dev/console

VIS_POD_CIDR_NETWORK="$(python3 - "${POD_CIDR_NETWORK}" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)
if network.version != 4 or network.prefixlen > 24:
    raise SystemExit("VIS pod CIDR must be IPv4 with a /24 or shorter prefix")
print(network.with_prefixlen)
PY
)"

if [ -d /etc/docker ]; then
  cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "/opt/vis/data/registry/docker",
  "features": {
    "containerd-snapshotter": false
  },
  "default-address-pools": [
    {
      "base": "${VIS_POD_CIDR_NETWORK}",
      "size": 24
    }
  ]
}
EOF
  systemctl restart docker.service || true
fi

install -d -o root -g root -m 0750 /opt/vis/config
openssl rand -hex 32 > /opt/vis/config/app-secret
chmod 0600 /opt/vis/config/app-secret
VIS_SECRET_KEY="$(cat /opt/vis/config/app-secret)"

mkdir -p /etc/systemd/system/vis-web.service.d
cat > /etc/systemd/system/vis-web.service.d/firstboot-env.conf <<EOF
[Service]
Environment=VIS_APPLIANCE_FQDN=${HOSTNAME}
Environment=VIS_APPLIANCE_IP=${IP_ADDRESS}
Environment=VIS_ADMIN_USERNAME=${VIS_ADMIN_USERNAME}
Environment=VIS_ADMIN_PASSWORD=
Environment=VIS_SECRET_KEY=${VIS_SECRET_KEY}
Environment=VIS_POD_CIDR_NETWORK=${VIS_POD_CIDR_NETWORK}
EOF

printf '%s\0%s\0' "${VIS_ADMIN_USERNAME}" "${VIS_ADMIN_PASSWORD}" | \
  PYTHONPATH=/opt/vis/app VIS_DB_PATH=/opt/vis/state/vis.db /opt/vis/app/venv/bin/python -c '
import sys
from werkzeug.security import generate_password_hash
from vis.store import ServiceStore
username, password, _ = sys.stdin.buffer.read().decode().split("\0")
store = ServiceStore()
store.initialize()
store.ensure_initial_admin(username, generate_password_hash(password))
'

unset VIS_ADMIN_PASSWORD
systemctl daemon-reload
systemctl enable vis-web.service vis-redirect.service
systemctl restart vis-web.service vis-redirect.service
