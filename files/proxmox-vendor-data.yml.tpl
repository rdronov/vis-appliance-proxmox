#cloud-config
write_files:
  - path: /etc/vis/firstboot.json
    owner: root:root
    permissions: "0600"
    encoding: b64
    content: __VIS_FIRSTBOOT_JSON_B64__
