#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

PACKER_TEMPLATE="packer/vis.pkr.hcl"
PACKER_VAR_FILE="${1:-${PACKER_VAR_FILE:-packer/proxmox.pkrvars.hcl}}"

if ! command -v packer >/dev/null 2>&1; then
  echo "packer is required: https://developer.hashicorp.com/packer/install" >&2
  exit 1
fi

if [ ! -f "${PACKER_VAR_FILE}" ]; then
  echo "Packer variable file not found: ${PACKER_VAR_FILE}" >&2
  echo "Create it with: cp packer/proxmox.pkrvars.hcl.example packer/proxmox.pkrvars.hcl" >&2
  exit 1
fi

if grep -q "replace-with-" "${PACKER_VAR_FILE}"; then
  echo "Replace all placeholder credentials in ${PACKER_VAR_FILE} before building." >&2
  exit 1
fi

echo "> Initializing the Proxmox Packer plugin..."
packer init "${PACKER_TEMPLATE}"

echo "> Validating the Proxmox-native VIS template..."
packer fmt -check "${PACKER_TEMPLATE}"
packer validate -var-file="${PACKER_VAR_FILE}" "${PACKER_TEMPLATE}"

echo "> Building VIS directly on Proxmox VE..."
packer build -var-file="${PACKER_VAR_FILE}" "${PACKER_TEMPLATE}"

echo "> Build complete. The resulting VMID is a Proxmox VE template; no VMDK, OVF, or OVA conversion was performed."
