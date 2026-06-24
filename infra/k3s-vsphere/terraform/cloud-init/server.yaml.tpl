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
      token: "${k3s_token}"
      write-kubeconfig-mode: "0600"
      tls-san:
        - "${server_ip}"
        - "${hostname}.${domain}"
      node-label:
        - "node-role.dockerelk.io/control-plane=true"

runcmd:
  - [sh, -c, "curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh"]
  - [sh, -c, "INSTALL_K3S_VERSION='${k3s_version}' sh /tmp/install-k3s.sh server"]
  - [sh, -c, "systemctl enable --now k3s"]

final_message: "K3s server ${hostname} initialise."
