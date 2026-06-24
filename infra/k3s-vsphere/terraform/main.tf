data "vsphere_datacenter" "target" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "target" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.target.id
}

data "vsphere_datastore" "target" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.target.id
}

data "vsphere_network" "target" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.target.id
}

data "vsphere_virtual_machine" "ubuntu" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.target.id
}

resource "vsphere_virtual_machine" "k3s" {
  for_each = var.nodes

  name             = each.key
  folder           = var.vm_folder != "" ? var.vm_folder : null
  resource_pool_id = data.vsphere_compute_cluster.target.resource_pool_id
  datastore_id     = data.vsphere_datastore.target.id

  num_cpus = each.value.num_cpus
  memory   = each.value.memory_mb
  guest_id = data.vsphere_virtual_machine.ubuntu.guest_id

  scsi_type = data.vsphere_virtual_machine.ubuntu.scsi_type

  network_interface {
    network_id   = data.vsphere_network.target.id
    adapter_type = data.vsphere_virtual_machine.ubuntu.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_size_gb
    thin_provisioned = true
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.ubuntu.id

    customize {
      linux_options {
        host_name = each.key
        domain    = var.domain
      }

      network_interface {
        ipv4_address = each.value.ipv4_address
        ipv4_netmask = each.value.ipv4_netmask
      }

      ipv4_gateway    = var.ipv4_gateway
      dns_server_list = var.dns_servers
      dns_suffix_list = [var.domain]
    }
  }

  extra_config = {
    "guestinfo.userdata" = base64encode(templatefile(
      "${path.module}/cloud-init/${each.value.role}.yaml.tpl",
      {
        hostname       = each.key
        domain         = var.domain
        ssh_public_key = var.ssh_public_key
        k3s_token      = var.k3s_token
        k3s_version    = var.k3s_version
        server_ip      = var.nodes["k3s-server-1"].ipv4_address
      }
    ))
    "guestinfo.userdata.encoding" = "base64"
  }

  wait_for_guest_ip_timeout  = 10
  wait_for_guest_net_timeout = 10

  lifecycle {
    ignore_changes = [vapp]

    precondition {
      condition     = each.value.role != "server" || each.key == "k3s-server-1"
      error_message = "Cette topologie mono-control-plane n'accepte qu'un serveur nomme k3s-server-1."
    }
  }
}
