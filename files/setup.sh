#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/vis/firstboot.json"
COMPLETE_MARKER="/var/lib/vis/firstboot.complete"

if [ -e "${COMPLETE_MARKER}" ]; then
  exit 0
fi

if [ ! -s "${CONFIG_FILE}" ]; then
  echo "VIS first-boot configuration is missing: ${CONFIG_FILE}" >&2
  exit 1
fi

mapfile -d '' VIS_VALUES < <(python3 - "${CONFIG_FILE}" <<'PY'
import ipaddress
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

required = (
    "fqdn",
    "ip_address",
    "gateway",
    "dns_servers",
    "search_domain",
    "ntp_server",
    "admin_username",
    "admin_password",
    "pod_cidr",
)
missing = [key for key in required if not data.get(key)]
if missing:
    raise SystemExit("missing VIS first-boot settings: " + ", ".join(missing))

fqdn = str(data["fqdn"]).lower()
if "." not in fqdn or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*[a-z0-9]", fqdn):
    raise SystemExit("invalid VIS FQDN")
ip_address = ipaddress.ip_address(str(data["ip_address"]))
if ip_address.version != 4:
    raise SystemExit("VIS requires an IPv4 management address")
pod_cidr = ipaddress.ip_network(str(data["pod_cidr"]), strict=False)
if pod_cidr.version != 4 or pod_cidr.prefixlen > 24:
    raise SystemExit("invalid VIS pod CIDR")
admin_username = str(data["admin_username"])
if not re.fullmatch(r"[A-Za-z0-9_-]{3,32}", admin_username):
    raise SystemExit("invalid VIS administrator username")
admin_password = str(data["admin_password"])
if len(admin_password) < 12:
    raise SystemExit("VIS administrator password must contain at least 12 characters")

values = (
    fqdn,
    str(ip_address),
    str(data["gateway"]),
    " ".join(str(item) for item in data["dns_servers"]),
    str(data["search_domain"]).lower(),
    str(data["ntp_server"]),
    admin_username,
    admin_password,
    str(pod_cidr),
    "true" if data.get("os_password_enabled") else "false",
)
sys.stdout.buffer.write(b"\0".join(value.encode() for value in values) + b"\0")
PY
)

if [ "${#VIS_VALUES[@]}" -ne 10 ]; then
  echo "Unable to parse VIS first-boot configuration." >&2
  exit 1
fi

HOSTNAME="${VIS_VALUES[0]}"
IP_ADDRESS="${VIS_VALUES[1]}"
GATEWAY="${VIS_VALUES[2]}"
DNS_SERVERS="${VIS_VALUES[3]}"
DNS_DOMAIN="${VIS_VALUES[4]}"
NTP_SERVER="${VIS_VALUES[5]}"
VIS_ADMIN_USERNAME="${VIS_VALUES[6]}"
VIS_ADMIN_PASSWORD="${VIS_VALUES[7]}"
POD_CIDR_NETWORK="${VIS_VALUES[8]}"
OS_PASSWORD_ENABLED="${VIS_VALUES[9]}"

echo -e "\e[92mStarting Proxmox-native VIS customization...\e[0m" > /dev/console
. /root/setup/setup-01-os.sh
. /root/setup/setup-02-network.sh
. /root/setup/setup-03-vis.sh

install -d -o root -g root -m 0755 /var/lib/vis
touch "${COMPLETE_MARKER}"
rm -f "${CONFIG_FILE}"
find /var/lib/cloud/instances -maxdepth 2 -type f \( -name 'vendor-data*' -o -name 'user-data*' \) -delete 2>/dev/null || true
unset VIS_ADMIN_PASSWORD

echo -e "\e[92mVIS customization completed.\e[0m" > /dev/console
