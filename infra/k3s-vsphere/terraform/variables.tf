variable "vsphere_user" {
  description = "Compte vCenter autorise a cloner et configurer des VMs."
  type        = string
}

variable "vsphere_password" {
  description = "Mot de passe du compte vCenter."
  type        = string
  sensitive   = true
}

variable "vsphere_server" {
  description = "FQDN ou adresse IP du vCenter."
  type        = string
}

variable "allow_unverified_ssl" {
  description = "Autorise un certificat vCenter non verifie. A reserver au laboratoire."
  type        = bool
  default     = false
}

variable "datacenter" {
  type = string
}

variable "cluster" {
  type = string
}

variable "datastore" {
  type = string
}

variable "network" {
  type = string
}

variable "template_name" {
  description = "Template Ubuntu 22.04 cloud-init avec open-vm-tools."
  type        = string
  default     = "ubuntu-2204-cloudinit-template"
}

variable "vm_folder" {
  description = "Dossier vCenter cible. Une valeur vide utilise la racine du datacenter."
  type        = string
  default     = ""
}

variable "domain" {
  description = "Domaine DNS applique aux VMs."
  type        = string
}

variable "ipv4_gateway" {
  type = string
}

variable "dns_servers" {
  type = list(string)

  validation {
    condition     = length(var.dns_servers) > 0
    error_message = "Au moins un serveur DNS est requis."
  }
}

variable "ssh_public_key" {
  description = "Cle publique autorisee pour l'utilisateur ubuntu."
  type        = string
}

variable "k3s_token" {
  description = "Secret partage entre le serveur et les agents K3s."
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "Version K3s explicite, par exemple v1.33.1+k3s1."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version doit respecter le format vX.Y.Z+k3sN."
  }
}

variable "nodes" {
  description = "Topologie K3s. La cle k3s-server-1 est obligatoire."
  type = map(object({
    role         = string
    ipv4_address = string
    ipv4_netmask = number
    num_cpus     = number
    memory_mb    = number
    disk_size_gb = number
  }))

  validation {
    condition     = contains(keys(var.nodes), "k3s-server-1")
    error_message = "Le noeud k3s-server-1 doit etre defini."
  }

  validation {
    condition     = alltrue([for node in values(var.nodes) : contains(["server", "agent"], node.role)])
    error_message = "Le role de chaque noeud doit etre server ou agent."
  }
}
