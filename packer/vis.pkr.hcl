packer {
  required_version = ">= 1.11.0"

  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.2"
    }
  }
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL, including /api2/json."
}

variable "proxmox_username" {
  type        = string
  sensitive   = true
  description = "Proxmox API token identity, for example packer@pve!vis-builder."
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret."
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node on which to build the template."
}

variable "proxmox_storage" {
  type        = string
  description = "Proxmox storage ID for the template disks and cloud-init drive."
}

variable "proxmox_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Bridge used by the temporary Packer build VM."
}

variable "insecure_skip_tls_verify" {
  type        = bool
  default     = false
  description = "Allow a self-signed Proxmox API certificate. Prefer installing the PVE CA instead."
}

variable "template_vmid" {
  type        = number
  description = "Cluster-unique VMID assigned to the resulting Proxmox template."
}

variable "version" {
  type    = string
  default = "1.0.3-pve.1"
}

variable "template_name" {
  type    = string
  default = "vcf-infrastructure-services-appliance-pve"
}

variable "iso_file" {
  type        = string
  default     = "local:iso/ubuntu-26.04-live-server-amd64.iso"
  description = "Ubuntu Server ISO already present on Proxmox storage."
}

variable "iso_checksum" {
  type    = string
  default = "sha256:dec49008a71f6098d0bcfc822021f4d042d5f2db279e4d75bdd981304f1ca5d9"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "cpu_type" {
  type        = string
  default     = "host"
  description = "Proxmox CPU model. Use a cluster-wide model instead of host for heterogeneous live migration."
}

variable "os_disk_size" {
  type    = string
  default = "40G"
}

variable "depot_disk_size" {
  type    = string
  default = "200G"
}

variable "sftp_disk_size" {
  type    = string
  default = "15G"
}

variable "registry_disk_size" {
  type    = string
  default = "60G"
}

variable "dns_disk_size" {
  type    = string
  default = "2G"
}

variable "identity_disk_size" {
  type    = string
  default = "2G"
}

variable "guest_username" {
  type    = string
  default = "visadmin"
}

variable "guest_password" {
  type        = string
  sensitive   = true
  description = "Temporary Packer build password; it is invalidated before template creation."
}

variable "guest_password_hash" {
  type        = string
  sensitive   = true
  description = "SHA-512 crypt hash of guest_password for Ubuntu autoinstall."
}

variable "install_vcf_download_tool" {
  type    = bool
  default = false
}

variable "harbor_version" {
  type    = string
  default = "v2.15.1"
}

variable "harbor_port" {
  type    = number
  default = 9443
}

variable "harbor_http_port" {
  type    = number
  default = 9080
}

variable "keycloak_image" {
  type    = string
  default = "quay.io/keycloak/keycloak:26.3"
}

source "proxmox-iso" "vis" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  task_timeout             = "30m"

  vm_id                = var.template_vmid
  vm_name              = "${var.template_name}-build"
  template_name        = "${var.template_name}-${var.version}"
  template_description = "VCF Infrastructure Services Appliance ${var.version}; built natively on Proxmox VE with Packer"
  tags                 = "vis;vcf;appliance;template"

  os                 = "l26"
  machine            = "q35"
  bios               = "seabios"
  sockets            = 1
  cores              = var.cores
  cpu_type           = var.cpu_type
  memory             = var.memory
  ballooning_minimum = 0

  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  onboot          = false

  cloud_init                          = true
  cloud_init_storage_pool             = var.proxmox_storage
  cloud_init_disk_type                = "ide"
  cloud_init_disable_upgrade_packages = true

  boot_iso {
    type         = "scsi"
    iso_file     = var.iso_file
    iso_checksum = var.iso_checksum
    unmount      = true
  }

  network_adapters {
    model  = "virtio"
    bridge = var.proxmox_bridge
  }

  disks {
    type         = "scsi"
    disk_size    = var.os_disk_size
    storage_pool = var.proxmox_storage
    format       = "raw"
    discard      = true
    io_thread    = true
    ssd          = true
  }

  disks {
    type         = "scsi"
    disk_size    = var.depot_disk_size
    storage_pool = var.proxmox_storage
    format       = "raw"
    discard      = true
    io_thread    = true
    ssd          = true
  }

  disks {
    type         = "scsi"
    disk_size    = var.sftp_disk_size
    storage_pool = var.proxmox_storage
    format       = "raw"
    discard      = true
    io_thread    = true
    ssd          = true
  }

  disks {
    type         = "scsi"
    disk_size    = var.registry_disk_size
    storage_pool = var.proxmox_storage
    format       = "raw"
    discard      = true
    io_thread    = true
    ssd          = true
  }

  disks {
    type         = "scsi"
    disk_size    = var.dns_disk_size
    storage_pool = var.proxmox_storage
    format       = "raw"
    discard      = true
    io_thread    = true
    ssd          = true
  }

  disks {
    type         = "scsi"
    disk_size    = var.identity_disk_size
    storage_pool = var.proxmox_storage
    format       = "raw"
    discard      = true
    io_thread    = true
    ssd          = true
  }

  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]
  http_content = {
    "/meta-data" = file("../http/meta-data")
    "/user-data" = replace(
      file("../http/user-data"),
      "__VIS_BUILD_PASSWORD_HASH__",
      var.guest_password_hash
    )
  }

  ssh_username = var.guest_username
  ssh_password = var.guest_password
  ssh_port     = 22
  ssh_timeout  = "90m"

}

build {
  sources = ["source.proxmox-iso.vis"]

  provisioner "shell-local" {
    inline = [
      "rm -rf http/optional-artifacts",
      "mkdir -p http/optional-artifacts",
      "touch http/optional-artifacts/.keep",
      "sh -c 'if [ \"${var.install_vcf_download_tool}\" = \"true\" ]; then set -- artifacts/vcf-download-tool-*; if [ -e \"$1\" ]; then cp \"$1\" http/optional-artifacts/vcf-download-tool-local.tar.gz; else : > http/optional-artifacts/vcf-download-tool-local.tar.gz; fi; else : > http/optional-artifacts/vcf-download-tool-local.tar.gz; fi'"
    ]
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    scripts         = ["scripts/vis-settings.sh"]
  }

  provisioner "file" {
    source      = "http/optional-artifacts"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "vis"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "files/vis-redirect.service"
    destination = "/tmp/vis-redirect.service"
  }

  provisioner "file" {
    source      = "scripts/vis-update.sh"
    destination = "/tmp/vis-update.sh"
  }

  provisioner "file" {
    source      = "scripts/vis-apply-update.sh"
    destination = "/tmp/vis-apply-update.sh"
  }

  provisioner "file" {
    source      = "scripts/vis-offline-update.sh"
    destination = "/tmp/vis-offline-update.sh"
  }

  provisioner "file" {
    source      = "files/vis-update-signing.pub"
    destination = "/tmp/vis-update-signing.pub"
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    environment_vars = [
      "VIS_INSTALL_VCF_DOWNLOAD_TOOL=${var.install_vcf_download_tool}",
      "VIS_OPTIONAL_ARTIFACT_DIR=/tmp/optional-artifacts"
    ]
    scripts = ["scripts/vis-download-tool.sh"]
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    environment_vars = [
      "VIS_APPLIANCE_FQDN=vis-template.invalid",
      "VIS_APPLIANCE_IP=127.0.0.1",
      "VIS_ADMIN_USERNAME=",
      "VIS_ADMIN_PASSWORD=",
      "VIS_SFTP_USER=",
      "VIS_SFTP_PASSWORD="
    ]
    scripts = ["scripts/vis-services.sh"]
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    environment_vars = [
      "VIS_APPLIANCE_FQDN=vis-template.invalid",
      "VIS_APPLIANCE_IP=127.0.0.1",
      "VIS_POD_CIDR_NETWORK=10.10.0.0/16",
      "HARBOR_VERSION=${var.harbor_version}",
      "VIS_KEYCLOAK_IMAGE=${var.keycloak_image}",
      "VIS_HARBOR_PORT=${var.harbor_port}",
      "VIS_HARBOR_HTTP_PORT=${var.harbor_http_port}",
      "VIS_HARBOR_ADMIN_PASSWORD="
    ]
    scripts = ["scripts/vis-harbor.sh"]
  }

  provisioner "file" {
    sources = [
      "files/setup.sh",
      "files/setup-01-os.sh",
      "files/setup-02-network.sh",
      "files/setup-03-vis.sh"
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    scripts         = ["scripts/vis-firstboot.sh"]
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    scripts         = ["scripts/vis-cleanup.sh"]
  }

  provisioner "shell" {
    inline            = ["sudo -n /usr/sbin/shutdown -P now"]
    expect_disconnect = true
  }
}
