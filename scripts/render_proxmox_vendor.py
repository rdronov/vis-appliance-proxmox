#!/usr/bin/env python3
"""Validate VIS deployment settings and emit base64-encoded first-boot JSON."""

import base64
import ipaddress
import json
import os
import re


def required(name):
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"{name} is required")
    return value


fqdn = required("VIS_FQDN")
ip_cidr = required("VIS_IP_CIDR")
gateway = required("VIS_GATEWAY")
dns_servers = required("VIS_DNS_SERVERS")
search_domain = required("VIS_SEARCH_DOMAIN")
ntp_server = required("VIS_NTP_SERVER")
admin_username = required("VIS_ADMIN_USERNAME")
admin_password = required("VIS_ADMIN_PASSWORD")
pod_cidr = required("VIS_POD_CIDR_NETWORK")

interface = ipaddress.ip_interface(ip_cidr)
if interface.version != 4:
    raise SystemExit("VIS_IP_CIDR must be IPv4")
gateway_address = ipaddress.ip_address(gateway)
if gateway_address.version != 4 or gateway_address not in interface.network:
    raise SystemExit("VIS_GATEWAY must be an IPv4 address in VIS_IP_CIDR")
pod_network = ipaddress.ip_network(pod_cidr, strict=False)
if pod_network.version != 4 or pod_network.prefixlen > 24:
    raise SystemExit("VIS_POD_CIDR_NETWORK must be IPv4 with a /24 or shorter prefix")
if pod_network.overlaps(interface.network):
    raise SystemExit("VIS_POD_CIDR_NETWORK must not overlap VIS_IP_CIDR")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]", fqdn) or "." not in fqdn:
    raise SystemExit("VIS_FQDN must be a valid fully qualified domain name")
if not re.fullmatch(r"[A-Za-z0-9_-]{3,32}", admin_username):
    raise SystemExit("VIS_ADMIN_USERNAME must be 3-32 letters, numbers, dashes, or underscores")
if len(admin_password) < 12:
    raise SystemExit("VIS_ADMIN_PASSWORD must contain at least 12 characters")
dns_addresses = [str(ipaddress.ip_address(item)) for item in dns_servers.split()]
if not dns_addresses:
    raise SystemExit("VIS_DNS_SERVERS must contain at least one IP address")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]", search_domain):
    raise SystemExit("VIS_SEARCH_DOMAIN is invalid")
try:
    ipaddress.ip_address(ntp_server)
except ValueError:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]", ntp_server):
        raise SystemExit("VIS_NTP_SERVER must be an IP address or hostname")

payload = {
    "fqdn": fqdn.lower(),
    "ip_address": str(interface.ip),
    "ip_cidr": str(interface),
    "gateway": str(gateway_address),
    "dns_servers": dns_addresses,
    "search_domain": search_domain.lower(),
    "ntp_server": ntp_server,
    "admin_username": admin_username,
    "admin_password": admin_password,
    "pod_cidr": str(pod_network),
    "os_password_enabled": os.environ.get("VIS_OS_PASSWORD_ENABLED") == "true",
}
encoded = base64.b64encode(json.dumps(payload, separators=(",", ":")).encode())
print(encoded.decode())
