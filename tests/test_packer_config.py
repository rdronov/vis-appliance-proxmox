import base64
import json
import os
import re
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ProxmoxPackerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packer = (ROOT / "packer" / "vis.pkr.hcl").read_text(encoding="utf-8")
        cls.deploy = (ROOT / "scripts" / "deploy_vis_proxmox.sh").read_text(encoding="utf-8")

    def test_builder_is_proxmox_native(self):
        self.assertIn('source "proxmox-iso" "vis"', self.packer)
        self.assertIn('source  = "github.com/hashicorp/proxmox"', self.packer)
        self.assertIn('sources = ["source.proxmox-iso.vis"]', self.packer)
        for vmware_term in ("vmware-iso", "ovftool", "output-vmware-iso", "vmdk", "open-vm-tools"):
            self.assertNotIn(vmware_term, self.packer.lower())

    def test_builder_creates_a_pve_template_with_cloud_init_and_agent(self):
        self.assertIn("template_name", self.packer)
        self.assertIn("cloud_init                          = true", self.packer)
        self.assertIn("cloud_init_storage_pool             = var.proxmox_storage", self.packer)
        self.assertIn("qemu_agent      = true", self.packer)
        self.assertNotIn("skip_convert_to_template", self.packer)

    def test_default_proxmox_names_are_short(self):
        template_name = re.search(
            r'variable "template_name" \{.*?default = "([^"]+)"',
            self.packer,
            re.DOTALL,
        ).group(1)
        version = re.search(
            r'variable "version" \{.*?default = "([^"]+)"',
            self.packer,
            re.DOTALL,
        ).group(1)

        self.assertEqual("vis-pve", template_name)
        self.assertLessEqual(len(f"{template_name}-build"), 40)
        self.assertLessEqual(len(f"{template_name}-{version}"), 40)

    def test_builder_uses_six_direct_proxmox_disks(self):
        self.assertEqual(6, self.packer.count('  disks {'))
        self.assertEqual(6, self.packer.count('    format       = "raw"'))
        self.assertIn('scsi_controller = "virtio-scsi-single"', self.packer)
        for size in ("40G", "200G", "15G", "60G", "2G"):
            self.assertIn(f'default = "{size}"', self.packer)

    def test_autoinstall_password_is_injected_not_committed(self):
        user_data = (ROOT / "http" / "user-data").read_text(encoding="utf-8")
        example = (ROOT / "packer" / "proxmox.pkrvars.hcl.example").read_text(encoding="utf-8")
        self.assertIn('password: "__VIS_BUILD_PASSWORD_HASH__"', user_data)
        self.assertIn('"__VIS_BUILD_PASSWORD_HASH__"', self.packer)
        self.assertIn("guest_password_hash", example)
        self.assertNotIn("VMware1!", user_data)
        self.assertNotIn("VMware1!", example)

    def test_autoinstall_partitions_all_service_disks(self):
        user_data = (ROOT / "http" / "user-data").read_text(encoding="utf-8")
        self.assertIn("- qemu-guest-agent", user_data)
        self.assertIn("systemctl, enable, qemu-guest-agent", user_data)
        for device in ("/dev/sda", "/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde", "/dev/sdf"):
            self.assertIn(f"path: {device}", user_data)
        for mount in (
            "/opt/vis/state",
            "/opt/vis/data/depot",
            "/opt/vis/data/sftp",
            "/opt/vis/data/registry",
            "/opt/vis/data/dns",
            "/opt/vis/data/identity",
        ):
            self.assertIn(f"path: {mount}", user_data)

    def test_autoinstall_late_commands_are_command_lists(self):
        user_data = (ROOT / "http" / "user-data").read_text(encoding="utf-8")

        self.assertNotIn("    - curtin in-target", user_data)
        self.assertIn(
            "    - [curtin, in-target, --target=/target, --, systemctl, enable, ssh]",
            user_data,
        )
        self.assertIn(
            '    - [curtin, in-target, --target=/target, --, /bin/sh, -c, "echo \'visadmin ALL=(ALL) NOPASSWD: ALL\' > /etc/sudoers.d/99-vis-packer && chmod 0440 /etc/sudoers.d/99-vis-packer"]',
            user_data,
        )

    def test_optional_vcf_download_tool_is_staged_after_install(self):
        self.assertIn("vcf-download-tool-*", self.packer)
        self.assertIn('source      = "http/optional-artifacts"', self.packer)
        self.assertIn("VIS_OPTIONAL_ARTIFACT_DIR=/tmp/optional-artifacts", self.packer)
        self.assertIn("VIS_INSTALL_VCF_DOWNLOAD_TOOL=${var.install_vcf_download_tool}", self.packer)

    def test_template_is_sealed_for_safe_cloning(self):
        cleanup = (ROOT / "scripts" / "vis-cleanup.sh").read_text(encoding="utf-8")
        for expected in (
            "passwd -l visadmin",
            "/etc/ssh/ssh_host_*",
            "truncate -s 0 /etc/machine-id",
            "cloud-init clean --logs --seed",
            "/opt/vis/state/vis.db",
            "/opt/vis/config/app-secret",
            "fstrim -av",
        ):
            self.assertIn(expected, cleanup)
        self.assertNotIn("dd if=/dev/zero", cleanup)

    def test_firstboot_consumes_cloud_init_not_ovf_guestinfo(self):
        firstboot = (ROOT / "scripts" / "vis-firstboot.sh").read_text(encoding="utf-8")
        setup = (ROOT / "files" / "setup.sh").read_text(encoding="utf-8")
        self.assertIn("After=cloud-final.service", firstboot)
        self.assertIn("qemu-guest-agent.service", firstboot)
        self.assertIn("/etc/vis/firstboot.json", setup)
        self.assertIn("/var/lib/vis/firstboot.complete", setup)
        self.assertNotIn("guestinfo", firstboot.lower() + setup.lower())
        self.assertNotIn("ovf", firstboot.lower() + setup.lower())

    def test_firstboot_seeds_admin_then_drops_plaintext_password(self):
        setup = (ROOT / "files" / "setup-03-vis.sh").read_text(encoding="utf-8")
        self.assertIn("generate_password_hash", setup)
        self.assertIn("ensure_initial_admin", setup)
        self.assertIn("Environment=VIS_ADMIN_PASSWORD=", setup)
        self.assertNotIn("Environment=VIS_ADMIN_PASSWORD=${VIS_ADMIN_PASSWORD}", setup)
        self.assertIn("unset VIS_ADMIN_PASSWORD", setup)

    def test_key_only_os_access_keeps_sudo_usable(self):
        setup = (ROOT / "files" / "setup-01-os.sh").read_text(encoding="utf-8")
        self.assertIn("passwd -l visadmin", setup)
        self.assertIn("90-visadmin-cloud", setup)
        self.assertIn("visadmin ALL=(ALL) NOPASSWD: ALL", setup)

    def test_guest_packages_are_for_kvm(self):
        settings = (ROOT / "scripts" / "vis-settings.sh").read_text(encoding="utf-8")
        self.assertIn("qemu-guest-agent", settings)
        self.assertNotIn("open-vm-tools", settings)
        for package in ("unbound", "slapd", "chrony", "dnsmasq-base", "linuxptp"):
            self.assertIn(package, settings)

    def test_deploy_script_clones_and_customizes_template(self):
        for expected in (
            'qm "${CLONE_ARGS[@]}"',
            "--ipconfig0",
            "--nameserver",
            "--searchdomain",
            "--cicustom",
            "qm start",
            "qm agent",
            "--delete cicustom",
        ):
            self.assertIn(expected, self.deploy)
        self.assertNotIn("qm importdisk", self.deploy)
        self.assertNotIn("qemu-img", self.deploy)

    def test_deploy_script_has_no_default_credentials(self):
        example = (ROOT / "deploy" / "proxmox.env.example").read_text(encoding="utf-8")
        renderer = (ROOT / "scripts" / "render_proxmox_vendor.py").read_text(encoding="utf-8")
        self.assertIn("VIS_ADMIN_PASSWORD=", example)
        self.assertIn("VIS_OS_PASSWORD=", example)
        self.assertNotIn("VMware1!", example)
        self.assertIn("VIS_ADMIN_PASSWORD must contain at least 12 characters", renderer)

    def test_vendor_renderer_validates_and_encodes_firstboot_data(self):
        env = os.environ.copy()
        env.update(
            VIS_FQDN="vis.vcf.lab",
            VIS_IP_CIDR="172.30.0.9/24",
            VIS_GATEWAY="172.30.0.1",
            VIS_DNS_SERVERS="192.168.30.29 1.1.1.1",
            VIS_SEARCH_DOMAIN="vcf.lab",
            VIS_NTP_SERVER="pool.ntp.org",
            VIS_ADMIN_USERNAME="admin",
            VIS_ADMIN_PASSWORD="CorrectHorseBatteryStaple",
            VIS_POD_CIDR_NETWORK="10.10.0.0/16",
            VIS_OS_PASSWORD_ENABLED="false",
        )
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "render_proxmox_vendor.py")],
            env=env,
            text=True,
            capture_output=True,
            check=True,
        )
        payload = json.loads(base64.b64decode(result.stdout.strip()).decode())
        self.assertEqual("vis.vcf.lab", payload["fqdn"])
        self.assertEqual("172.30.0.9", payload["ip_address"])
        self.assertEqual(["192.168.30.29", "1.1.1.1"], payload["dns_servers"])
        self.assertFalse(payload["os_password_enabled"])

    def test_packer_installs_update_helpers(self):
        services = (ROOT / "scripts" / "vis-services.sh").read_text(encoding="utf-8")
        for helper in ("vis-update", "vis-apply-update", "vis-offline-update"):
            self.assertIn(f"/usr/local/sbin/{helper}", services)
            self.assertIn(f"scripts/{helper}.sh", self.packer)


if __name__ == "__main__":
    unittest.main()
