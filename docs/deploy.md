# Deploy

Deploy VIS by cloning the Packer-built Proxmox template. Proxmox Cloud-Init configures the guest account and network; a short-lived vendor-data snippet supplies VIS-specific settings to the first-boot service.

No image import or disk conversion is involved.

## Resource requirements

| Resource | Default |
| --- | ---: |
| CPU | 2 vCPU |
| Memory | 4 GB |
| Storage | 319 GB logical across six thin-provisioned disks |

Actual physical use is initially much smaller on thin-capable storage. Depot, registry, and backup consumption can grow substantially.

## Prepare snippet storage

The deployment helper runs on a Proxmox node and needs a directory-backed storage with the `Snippets` content type enabled. The default local path is `/var/lib/vz/snippets` and the default storage ID is `local`.

In the PVE UI, open **Datacenter > Storage**, edit the selected directory storage, and enable **Snippets**. In a cluster, use snippet storage accessible from the node that owns the VM.

## Configure a clone

On a Proxmox node, from a checkout of this repository:

```shell
cp deploy/proxmox.env.example deploy/my-vis.env
chmod 600 deploy/my-vis.env
```

Set at least:

- `TEMPLATE_VMID`: the VMID created by Packer.
- `VM_ID` and `VM_NAME`: unique values for the clone.
- `VIS_FQDN`, `VIS_IP_CIDR`, gateway, DNS, search domain, and NTP.
- `VIS_SSH_PUBLIC_KEY_FILE`, an OS password, or both. Key-only deployments lock password login and grant `visadmin` passwordless sudo; password deployments use normal password-backed sudo.
- A unique `VIS_ADMIN_PASSWORD` of at least 12 characters.
- A Docker pod CIDR that does not overlap the management network or VCF networks.

The sample contains no working default passwords and is ignored after it is copied to an `.env` filename.

## Create and start the appliance

```shell
sudo ./scripts/deploy_vis_proxmox.sh deploy/my-vis.env
```

The helper:

1. Validates VMIDs, IPv4 networking, FQDN, password length, and pod-network overlap.
2. Runs `qm clone` against the native Proxmox template.
3. Applies `ipconfig0`, DNS, search domain, guest account, SSH key, and QEMU Guest Agent settings.
4. Attaches VIS configuration as Cloud-Init vendor data and starts the VM.
5. Waits for QEMU Guest Agent, detaches the secret-bearing custom data, and removes its snippet from the host.

If the guest agent does not respond within ten minutes, the helper leaves the snippet in place and prints the exact cleanup command. Do not remove it until first-boot customization has completed.

Open VIS after DNS resolves the configured FQDN:

```text
http://vis.vcf.lab/
```

Port 80 redirects to the management application on port 8080.

## First-boot behavior

The `vis-firstboot.service` unit waits for `cloud-final.service`, validates that the actual guest address matches the requested address, generates a unique application secret, hashes the VIS administrator password into SQLite, removes the plaintext configuration, and starts the VIS UI. All managed supporting services remain disabled until configured in VIS.

Inspect failures from the Proxmox console or SSH:

```shell
sudo systemctl status vis-firstboot.service
sudo journalctl -u vis-firstboot.service -b
sudo cloud-init status --long
```

If the guest receives DHCP even though the PVE Cloud-Init panel shows a static
address, the template was built before installer-network cleanup was added.
Rebuild the template before creating more clones. For an existing clone, use
the PVE console to remove the stale installer network, write the intended
static netplan, and restart `vis-firstboot.service`. Applying netplan changes
the guest address and can disconnect an SSH session.

`docker0` can show `state DOWN` while Docker is running but no container is
attached to the bridge. This is expected immediately after deployment because
VIS supporting services remain disabled until they are configured and enabled
in the UI. Check the daemon independently with `systemctl is-active docker`.

## Resize a service disk

Resize the appropriate native PVE disk, for example the depot disk:

```shell
qm resize <vmid> scsi1 +100G
```

Then open **Appliance > System Health** in VIS and select **Expand Filesystem** for that partition. The disk mapping is `scsi1` depot, `scsi2` SFTP, `scsi3` registry, `scsi4` DNS, and `scsi5` identity.

## Linked versus full clones

`FULL_CLONE=true` is the default and gives the appliance independent storage. Set `FULL_CLONE=false` only when the selected Proxmox storage and backup design support linked clones and the template will remain immutable.
