#cloud-config
package_update: true
packages:
  - curl
  - ca-certificates

users:
  - default
  - name: ubuntu
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

write_files:
  - path: /etc/rancher/k3s/config.yaml
    owner: root:root
    permissions: "0600"
    content: |
      server: "https://${server_ip}:6443"
      token: "${k3s_token}"
      node-label:
        - "node-role.dockerelk.io/worker=true"

runcmd:
  - [sh, -c, "until curl -ksf https://${server_ip}:6443/ping; do sleep 10; done"]
  - [sh, -c, "curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh"]
  - [sh, -c, "INSTALL_K3S_VERSION='${k3s_version}' sh /tmp/install-k3s.sh agent"]
  - [sh, -c, "systemctl enable --now k3s-agent"]

final_message: "K3s agent ${hostname} initialise."
