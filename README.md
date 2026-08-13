# VCF Infrastructure Services Appliance for Proxmox VE

This fork builds the **VCF Infrastructure Services (VIS) Appliance** directly on Proxmox VE. Packer boots the Ubuntu Server ISO as a KVM guest, provisions VIS and its supporting services, seals the guest, and converts the VM into a Proxmox template. Deployments are full or linked PVE clones customized with Proxmox Cloud-Init and QEMU Guest Agent.


This project is based on William Lam's Apache-2.0-licensed [VCF Infrastructure Services Appliance](https://github.com/lamw/vcf-infrastructure-service-appliance). There is no VMDK conversion, OVF injection, OVA packaging, VMware guestinfo, or `open-vm-tools` dependency in the appliance lifecycle. VCF remains the consumer of the services; Proxmox VE is the hypervisor running the VIS appliance.

![VIS Appliance service summary](docs/images/vis-service-summary.png)

VIS provides:

- Software depot for VCF software binaries
- SFTP backup server
- Harbor container registry
- LDAP and OIDC identity providers
- DNS, NTP, and DHCP services
- KMIP-compatible key management service
- Shared TLS certificate management
- Appliance health, storage visibility, and configuration import/export

## Proxmox-native lifecycle

1. `packer/vis.pkr.hcl` uses HashiCorp's `proxmox-iso` builder against the PVE API.
2. Ubuntu autoinstall partitions six raw VirtIO-SCSI disks directly on Proxmox storage.
3. Packer installs VIS, Harbor, QEMU Guest Agent, Cloud-Init, and the service backends.
4. The guest is stripped of build credentials, SSH host keys, machine identity, VIS state, and application secrets.
5. Packer converts the completed VM into a cloud-init-enabled Proxmox template.
6. `scripts/deploy_vis_proxmox.sh` clones the template and supplies unique networking, OS access, VIS credentials, and application settings.

## Quick start

Build the template:

```shell
cp packer/proxmox.pkrvars.hcl.example packer/proxmox.pkrvars.hcl
# Edit the private variable file, including a temporary password and its SHA-512 crypt hash.
./build.sh
```

Deploy a clone from a Proxmox node:

```shell
cp deploy/proxmox.env.example deploy/my-vis.env
chmod 600 deploy/my-vis.env
# Edit the private deployment settings and credentials.
sudo ./scripts/deploy_vis_proxmox.sh deploy/my-vis.env
```

See [Build](docs/build.md), [Deploy](docs/deploy.md), and [Architecture](docs/architecture.md) for prerequisites and the full workflow.

> VIS is intended for VCF labs and proof-of-concept environments. Review the security posture, backup design, and availability requirements before using these services outside a lab.
