# you can add also meta_data field
resource "libvirt_cloudinit_disk" "host" {
  name           = "${var.hostname}_cloudinit.iso"
  user_data      = templatefile("${path.module}/../../cloud-init/cloud_init_host_setup.cfg", {
    hostname = var.hostname,
    interface_name = var.interface_name,
    dns_address = var.dns_address,
    domain = var.domain,
    ip_address = var.ip_address
    ip_address_gateway = var.ip_address_gateway,
    mac_address = var.mac_address
    ssh_public_key = var.ssh_public_key
    
  })
  pool           = var.pool
}


resource "libvirt_volume" "host" {
  name           = "${var.hostname}.qcow2"
  pool   = var.pool
  base_volume_id = var.base_image
  size = var.image_size
}


resource "libvirt_volume" "disk" {
  for_each = var.disk
  name           = "${var.hostname}_${each.key}.qcow2"
  pool   = each.value.pool
  size = each.value.image_size
}


resource "libvirt_domain" "host" {
  name = var.hostname
  memory = var.memory
  vcpu = var.vcpu
  autostart = var.autostart

  cloudinit = libvirt_cloudinit_disk.host.id

  cpu {
    mode = "host-passthrough"
  }

  # expects a console or will not boot
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.host.id
    scsi      = "true"
  }

  dynamic "disk" {
    for_each = libvirt_volume.disk
    content {
      volume_id = libvirt_volume.disk[disk.key].id
      scsi      = "true"
    }
  }

  dynamic "network_interface" {
    for_each = var.interfaces
    content {
      network_id = network_interface.value.network_id
      mac = network_interface.value.mac
    }
  }
}


variable "mac_address" { type = string }
variable "dns_address" { type = string }
variable "ssh_public_key" { type = string }
variable "domain" { type = string }
variable "ip_address" { type = string }
variable "ip_address_gateway" { type = string }
variable "hostname" { type = string }
variable "interface_name" { 
  type = string
  default = "enlan"
}
variable "image_size" { 
  type = number
  default = null
}

variable "autostart" { 
  type = bool
  default = true
}

variable "disk" { 
  type = map(object({
    pool = string
    image_size = number
  }))
  default = {}
}

variable "interfaces" { 
  type = list(object({
    network_id = string
    mac = string
    hostname = string
    addresses = list(string)
  }))
}

variable "memory" { 
  type = string
  default = "256"
}
variable "vcpu" { 
  type = number
  default = 1
}
variable "pool" { type = string }
variable "base_image" { type = string }

terraform {
  required_version = ">= 0.14.9"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.11"
    }
    template = {
      source = "hashicorp/template"
    }
  }
}

