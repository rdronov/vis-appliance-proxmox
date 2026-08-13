# Build

VIS is built natively on Proxmox VE with Packer's `proxmox-iso` builder. The build starts a new KVM VM from the Ubuntu Server ISO, creates all six service disks on Proxmox storage, provisions the appliance, seals it, and converts VMID into a Proxmox template.

No VMware image is imported or converted.

## Requirements

### Build workstation

- Packer 1.11 or newer.
- Network access to the Proxmox API on TCP 8006.
- TCP 8000-9000 from the temporary build VM to the workstation for Ubuntu autoinstall seed data.
- Enough time for Ubuntu packages, Harbor images, and Keycloak artifacts to download.

`packer init` installs HashiCorp's Proxmox plugin declared in `packer/vis.pkr.hcl`.

### Proxmox VE

- A node with KVM enabled.
- An ISO-capable storage containing the configured Ubuntu Server ISO.
- An image-capable storage with enough space for the six template disks.
- A bridge that gives the temporary build VM DHCP and internet access.
- A dedicated API token with access to create, configure, start, stop, and convert VMs and allocate space on the selected storage.

The token identity uses `user@realm!token-id`, for example `packer@pve!vis-builder`. Grant only the required scope. Typical privileges include VM allocation/audit/power/configuration, datastore audit/allocation, and bridge use; the exact ACL path depends on your pool, node, storage, and SDN design.

## Disk layout

Packer creates these disks directly on `proxmox_storage`:

| Proxmox device | Mount | Default size |
| --- | --- | ---: |
| `scsi0` | OS, `/var`, and `/opt/vis/state` LVM | 40 GB |
| `scsi1` | `/opt/vis/data/depot` | 200 GB |
| `scsi2` | `/opt/vis/data/sftp` | 15 GB |
| `scsi3` | `/opt/vis/data/registry` | 60 GB |
| `scsi4` | `/opt/vis/data/dns` | 2 GB |
| `scsi5` | `/opt/vis/data/identity` | 2 GB |

They use raw format, `virtio-scsi-single`, per-disk I/O threads, discard, and SSD emulation. The backing implementation remains native to the selected PVE storage, such as LVM-thin, ZFS, Ceph RBD, or directory storage.

## Configure the build

Copy the ignored sample file:

```shell
cp packer/proxmox.pkrvars.hcl.example packer/proxmox.pkrvars.hcl
chmod 600 packer/proxmox.pkrvars.hcl
```

Edit the PVE endpoint, token, node, storage, bridge, ISO location, and a cluster-unique template VMID. Never commit this file.

Ubuntu autoinstall needs a SHA-512 crypt hash matching the temporary Packer SSH password. Generate it locally:

```shell
openssl passwd -6
```

Put the plaintext value in `guest_password` and the generated `$6$...` value in `guest_password_hash`. The account is locked and its authorized keys are removed before template creation.

The ISO must already be visible to Proxmox. The default reference is:

```hcl
iso_file = "local:iso/ubuntu-26.04-live-server-amd64.iso"
```

The checksum is verified by the Packer builder. Update both the ISO reference and checksum when using a different release.

## Build

```shell
./build.sh
```

The script initializes the plugin, formats and validates the HCL, and runs the build. On success, `template_vmid` is a Proxmox template whose name includes the VIS version.

Packer does not emit a local disk image, VMDK, OVF, or OVA. The template disks remain on the configured Proxmox storage.

## Template sealing

Before Packer powers off the VM, `scripts/vis-cleanup.sh`:

- Locks the temporary build password and removes authorized keys.
- Removes SSH host keys and resets `/etc/machine-id`.
- Removes Subiquity/curtin installer DHCP state, then runs `cloud-init clean --logs --seed` so clones use Proxmox `ipconfig0` network data.
- Removes VIS database state and the application secret.
- Clears package caches and transient logs.
- Uses TRIM instead of zero-filling thin-provisioned service disks.

Each clone therefore gets a fresh Linux identity, SSH host keys, VIS database, administrator password hash, and Flask application secret.
