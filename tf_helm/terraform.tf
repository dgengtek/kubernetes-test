provider helm {
  kubernetes {
    config_path = "../terraform/admin.conf"
  }
}

resource helm_release nfs-provisioner {
  for_each = {
    for index, host in var.inventory: index => host
  }
  name       = "nfs-provisioner-${each.value.hostname}"

  repository = "https://kubernetes-sigs.github.io/nfs-ganesha-server-and-external-provisioner/"
  chart      = "nfs-server-provisioner"
  version = "1.3.2"

  set {
    name  = "fullnameOverride"
    value = "nfs-provisioner-${each.value.hostname}"
  }

  set {
    name  = "persistence.enabled"
    value = true
  }

  set {
    name  = "persistence.storageClass"
    value = "local-hdd"
  }

  set {
    name  = "persistence.size"
    value = "1Gi"
  }

  set {
    name  = "storageClass.create"
    value = true
  }

  set {
    name  = "storageClass.name"
    value = "nfs-${each.value.hostname}"
  }

  set {
    name  = "rbac.create"
    value = true
  }

  values = [
    yamlencode({
      nodeSelector = {
        "kubernetes.io/hostname" = each.value.hostname
      }
    }),
  ]

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
