module "k8-node" {
  for_each = {for index, host in var.inventory: index => host}
  hostname = each.value.hostname
  source = "./domain"

  pool = libvirt_pool.k8.name
  base_image = libvirt_volume.debian_11_kubernetes.id
  ssh_public_key = tls_private_key.ansible.public_key_openssh

  interface_name = "enlan"
  dns_address = cidrhost(local.ip_network, 1)
  domain = var.domain
  vcpu = each.value.vcpu
  memory = each.value.memory

  mac_address = "52:54:00:73:e8:b${each.key + 3}"
  ip_address = format("%s/%s", cidrhost(local.ip_network, each.key + 3), var.network_prefix)
  ip_address_gateway = cidrhost(local.ip_network, 1)

  disk = {
    data = {
      pool = libvirt_pool.k8.name
      image_size = 21474836480
    }
  }

  interfaces = [
    {
      hostname = each.value.hostname
      addresses = [cidrhost(local.ip_network, each.key + 3)]
      mac = "52:54:00:73:e8:b${each.key + 3}"
      network_id = libvirt_network.k8_network.id
    },
  ]
}


resource "libvirt_pool" "k8" {
  name = "test_k8"
  type = "dir"
  path = "/data/libvirt/pool/test_k8"
}


resource "libvirt_volume" "debian_11_kubernetes" {
  name   = "test_debian_11_kubernetes.qcow2"
  pool   = libvirt_pool.k8.name
  source = var.volume_source
}


resource "libvirt_network" "k8_network" {
  name = "test_k8_network"
  mode = "nat"

  domain = var.domain

  addresses = ["${local.ip_network}"]

  dns {
    enabled = true
    local_only = false

    dynamic "hosts" {
      for_each = {for index, host in var.inventory: index => host}
      content {
        hostname = hosts.value.hostname
        ip = hosts.value.ip
      }
    }

    hosts {
        hostname = "cpn"
        ip = cidrhost(local.ip_network, 2)
    }
  }

}

locals {
  ip_network = format("%s/%s", var.network, var.network_prefix)
}


data "libvirt_network_dns_host_template" "cpn" {
  count    = length(var.inventory)
  ip       = var.inventory[count.index].ip
  hostname = "cpn"
}


resource "tls_private_key" "ansible" {
  algorithm = "RSA"
}


resource "local_file" "ansible" {
  filename = "./id_ansible"
  file_permission = "600"
  sensitive_content = tls_private_key.ansible.private_key_pem
}


output "inventory" {
  value = var.inventory
}


resource "local_file" "inventory" {
  content = templatefile("./inventory.tpl", {
    inventory = var.inventory
    vip = cidrhost(local.ip_network, 2)
    cpn_api_ha_port = "6443"
    cpn_api_port = "6444"
    network_prefix = var.network_prefix
    keepalived_password = "verysecurepassword"
  })
  filename = "./inventory"
}
