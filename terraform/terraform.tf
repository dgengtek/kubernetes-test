terraform {
  required_version = ">= 1.0.10"
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


provider "libvirt" {
  uri = var.uri
}


variable "uri" {
  type = string
}

variable "volume_source" {
  type = string
}

variable "domain" {
  type = string
}

variable "network" {
  type = string
}

variable "network_prefix" {
  type = string
}

variable "inventory" { 
  type = list(object({
    hostname = string
    ip = string
    role = string
    vcpu = string
    memory = string
  }))
}
