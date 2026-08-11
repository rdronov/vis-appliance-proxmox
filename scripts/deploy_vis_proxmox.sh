#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/deploy_vis_proxmox.sh <private-config.env>

Clone the Packer-built VIS template, apply Proxmox Cloud-Init settings, and
start a new VIS appliance. Run this script on a Proxmox VE node.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

CONFIG_FILE="${1:-}"
if [ -z "${CONFIG_FILE}" ] || [ ! -f "${CONFIG_FILE}" ]; then
  usage >&2
  exit 2
fi

# The config is a shell environment file owned by the operator. It must not be
# committed because it contains deployment credentials.
# shellcheck disable=SC1090
source "${CONFIG_FILE}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_TEMPLATE="${REPO_ROOT}/files/proxmox-vendor-data.yml.tpl"
VENDOR_RENDERER="${REPO_ROOT}/scripts/render_proxmox_vendor.py"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_value() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Required setting is empty: ${name}" >&2
    exit 2
  fi
}

for command in qm pvesm python3 sed; do
  require_command "${command}"
done

for name in TEMPLATE_VMID VM_ID VM_NAME VIS_FQDN VIS_IP_CIDR VIS_GATEWAY VIS_DNS_SERVERS VIS_SEARCH_DOMAIN VIS_NTP_SERVER VIS_ADMIN_USERNAME VIS_ADMIN_PASSWORD VIS_POD_CIDR_NETWORK SNIPPET_STORAGE SNIPPET_DIR; do
  require_value "${name}"
done

VIS_OS_USER="${VIS_OS_USER:-visadmin}"
VIS_SSH_PUBLIC_KEY_FILE="${VIS_SSH_PUBLIC_KEY_FILE:-}"
VIS_OS_PASSWORD="${VIS_OS_PASSWORD:-}"
TARGET_STORAGE="${TARGET_STORAGE:-}"
FULL_CLONE="${FULL_CLONE:-true}"
START_VM="${START_VM:-true}"
ONBOOT="${ONBOOT:-true}"
KEEP_VENDOR_SNIPPET="${KEEP_VENDOR_SNIPPET:-false}"

case "${TEMPLATE_VMID}:${VM_ID}" in
  *[!0-9:]*|:*)
    echo "TEMPLATE_VMID and VM_ID must be numeric." >&2
    exit 2
    ;;
esac

if [ "${TEMPLATE_VMID}" = "${VM_ID}" ]; then
  echo "VM_ID must differ from TEMPLATE_VMID." >&2
  exit 2
fi

TEMPLATE_CONFIG="$(qm config "${TEMPLATE_VMID}" 2>/dev/null || true)"
if [ -z "${TEMPLATE_CONFIG}" ]; then
  echo "Template VMID does not exist: ${TEMPLATE_VMID}" >&2
  exit 1
fi
if ! grep -q '^template: 1$' <<<"${TEMPLATE_CONFIG}"; then
  echo "VMID ${TEMPLATE_VMID} exists but is not a Proxmox template." >&2
  exit 1
fi

if qm config "${VM_ID}" >/dev/null 2>&1; then
  echo "Target VMID already exists: ${VM_ID}" >&2
  exit 1
fi

if [ -n "${VIS_SSH_PUBLIC_KEY_FILE}" ] && [ ! -f "${VIS_SSH_PUBLIC_KEY_FILE}" ]; then
  echo "SSH public key file not found: ${VIS_SSH_PUBLIC_KEY_FILE}" >&2
  exit 2
fi

if [ -z "${VIS_SSH_PUBLIC_KEY_FILE}" ] && [ -z "${VIS_OS_PASSWORD}" ]; then
  echo "Set VIS_SSH_PUBLIC_KEY_FILE, VIS_OS_PASSWORD, or both." >&2
  exit 2
fi

if [ "${VIS_OS_USER}" != "visadmin" ]; then
  echo "VIS_OS_USER must be visadmin for this template." >&2
  exit 2
fi

if [ "${FULL_CLONE}" != "true" ] && [ -n "${TARGET_STORAGE}" ]; then
  echo "TARGET_STORAGE must be empty for a linked clone (FULL_CLONE=false)." >&2
  exit 2
fi

if ! pvesm status --storage "${SNIPPET_STORAGE}" >/dev/null 2>&1; then
  echo "Proxmox snippet storage is unavailable: ${SNIPPET_STORAGE}" >&2
  exit 1
fi

FIRSTBOOT_JSON_B64="$(
  VIS_FQDN="${VIS_FQDN}" \
  VIS_IP_CIDR="${VIS_IP_CIDR}" \
  VIS_GATEWAY="${VIS_GATEWAY}" \
  VIS_DNS_SERVERS="${VIS_DNS_SERVERS}" \
  VIS_SEARCH_DOMAIN="${VIS_SEARCH_DOMAIN}" \
  VIS_NTP_SERVER="${VIS_NTP_SERVER}" \
  VIS_ADMIN_USERNAME="${VIS_ADMIN_USERNAME}" \
  VIS_ADMIN_PASSWORD="${VIS_ADMIN_PASSWORD}" \
  VIS_POD_CIDR_NETWORK="${VIS_POD_CIDR_NETWORK}" \
  VIS_OS_PASSWORD_ENABLED="${VIS_OS_PASSWORD:+true}" \
  python3 "${VENDOR_RENDERER}"
)"
unset VIS_ADMIN_PASSWORD
SNIPPET_NAME="vis-${VM_ID}-vendor.yml"
SNIPPET_PATH="${SNIPPET_DIR%/}/${SNIPPET_NAME}"

mkdir -p "${SNIPPET_DIR}"
if [ ! -f "${VENDOR_TEMPLATE}" ]; then
  echo "Vendor-data template not found: ${VENDOR_TEMPLATE}" >&2
  exit 1
fi
sed "s|__VIS_FIRSTBOOT_JSON_B64__|${FIRSTBOOT_JSON_B64}|" "${VENDOR_TEMPLATE}" > "${SNIPPET_PATH}"
chmod 600 "${SNIPPET_PATH}"

cleanup_failed_deploy() {
  local status=$?
  if [ "${status}" -ne 0 ]; then
    echo "Deployment failed. The source template was not changed." >&2
    echo "Review VMID ${VM_ID} and secret-bearing snippet ${SNIPPET_PATH} before retrying." >&2
  fi
  exit "${status}"
}
trap cleanup_failed_deploy EXIT

CLONE_ARGS=(clone "${TEMPLATE_VMID}" "${VM_ID}" --name "${VM_NAME}")
if [ "${FULL_CLONE}" = "true" ]; then
  CLONE_ARGS+=(--full 1)
else
  CLONE_ARGS+=(--full 0)
fi
if [ -n "${TARGET_STORAGE}" ]; then
  CLONE_ARGS+=(--storage "${TARGET_STORAGE}")
fi

echo "> Cloning Proxmox template ${TEMPLATE_VMID} to VM ${VM_ID}..."
qm "${CLONE_ARGS[@]}"

ONBOOT_VALUE=0
if [ "${ONBOOT}" = "true" ]; then
  ONBOOT_VALUE=1
fi

SET_ARGS=(
  set "${VM_ID}"
  --agent enabled=1
  --ciuser "${VIS_OS_USER}"
  --ipconfig0 "ip=${VIS_IP_CIDR},gw=${VIS_GATEWAY}"
  --nameserver "${VIS_DNS_SERVERS}"
  --searchdomain "${VIS_SEARCH_DOMAIN}"
  --cicustom "vendor=${SNIPPET_STORAGE}:snippets/${SNIPPET_NAME}"
  --onboot "${ONBOOT_VALUE}"
  --description "VCF Infrastructure Services Appliance ${VIS_FQDN}"
)
if [ -n "${VIS_SSH_PUBLIC_KEY_FILE}" ]; then
  SET_ARGS+=(--sshkeys "${VIS_SSH_PUBLIC_KEY_FILE}")
fi
if [ -n "${VIS_OS_PASSWORD}" ]; then
  SET_ARGS+=(--cipassword "${VIS_OS_PASSWORD}")
fi

echo "> Applying Cloud-Init and VIS first-boot settings..."
qm "${SET_ARGS[@]}"

if [ "${START_VM}" = "true" ]; then
  echo "> Starting VM ${VM_ID}..."
  qm start "${VM_ID}"
fi

if [ "${START_VM}" = "true" ] && [ "${KEEP_VENDOR_SNIPPET}" != "true" ]; then
  echo "> Waiting for QEMU Guest Agent before detaching secret-bearing vendor data..."
  agent_ready=false
  for _ in $(seq 1 120); do
    if qm agent "${VM_ID}" ping >/dev/null 2>&1; then
      agent_ready=true
      break
    fi
    sleep 5
  done
  if [ "${agent_ready}" = "true" ]; then
    qm set "${VM_ID}" --delete cicustom >/dev/null
    rm -f "${SNIPPET_PATH}"
    echo "> Detached and removed the deployment vendor-data snippet."
  else
    echo "QEMU Guest Agent did not become ready within 10 minutes." >&2
    echo "Leave ${SNIPPET_PATH} attached until first boot completes, then run:" >&2
    echo "  qm set ${VM_ID} --delete cicustom && rm -f ${SNIPPET_PATH}" >&2
  fi
fi

trap - EXIT
echo "> VIS VM ${VM_ID} created: http://${VIS_FQDN}/"
