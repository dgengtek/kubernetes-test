# uri = "qemu+ssh://vmc@rack/system?sshauth=agent&known_hosts_verify=ignore"
uri = "qemu:///system"
domain = "k8.local"
network_prefix = "24"
network = "172.31.254.0"

inventory = [
  {
    "hostname" = "k8-node-1"
    "ip" = "172.31.254.3"
    "role" = "master"
    "vcpu" = 2
    "memory" = "2048"
  },
  {
    "hostname" = "k8-node-2"
    "ip" = "172.31.254.4"
    "role" = "cpn"
    "vcpu" = 2
    "memory" = "2048"
  },
  {
    "hostname" = "k8-node-3"
    "ip" = "172.31.254.5"
    "role" = "cpn"
    "vcpu" = 2
    "memory" = "2048"
  },
  {
    "hostname" = "k8-node-4"
    "ip" = "172.31.254.6"
    "role" = "node"
    "vcpu" = 1
    "memory" = "1024"
  }
]
