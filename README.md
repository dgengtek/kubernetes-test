# Kubernetes cluster for testing locally

This repository contains an automated kubernetes cluster setup.

* nodes run on a single libvirtd hypervisor
* high available, load balanced 3 control-plane 
  * keepalived, haproxy from static pods managed by kubernetes
* 1 worker node 
* nodes reachable from a nat network(172.31.254.0/24) from the hypervisor 
* used [terraform libvirtd provider](https://github.com/dmacvicar/terraform-provider-libvirt) 
* provisions the nodes with the forked ansible roles 
  * https://github.com/geerlingguy/ansible-role-docker 
  * https://github.com/geerlingguy/ansible-role-kubernetes

Provided are manifests to experiment with the cluster:

* ingress traefik daemonset on master nodes load balanced by haproxy with frontend <ha proxy port>:<host port>(80:10080, 443:10443, 9090:19090)
* traefik example service whoami(Host: whoami.k8.local)
* helm managed with terraform
  * nfs-provisioner(requires local-static-provisioner to be applied from ./manifests)


## Requirements

* docker
  * if running the tools without a docker container see the [dockerfile](Dockerfile)
* a hypervisor with 
  * [X86_virtualization](https://en.wikipedia.org/wiki/X86_virtualization)
  * [kvm](https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine)
  * libvirtd socket path /var/run/libvirt/libvirt-sock or pass the terraform variable TF_VAR_uri for a different location
* cloud-init image which uses systemd-networkd for network management
  * [packer-templates](https://github.com/dgengtek/packer-templates) contains configurations to build new images from a debian install to use for this repo
  * if you use prebuilt cloud-images provided by distributions
    you will need to replace the [cloud-init template file in this repository](cloud-init/cloud_init_host_setup.cfg) with an
    equivalent configuration for the network manager in the prebuilt image


## Setup kubernetes cluster environment

Export the required image location variable(TF_VAR_volume_source) for deployment to infrastructure.
The wrapper script `main.sh` builds the docker image with the terraform and ansible dependencies, applies infrastructure configuration and
runs the ansible playbook to join the nodes to the cluster and finally applies manifests found in ./manifests.

    # clone this repository and run commands from inside this repository
    export KUBERNETES_VERSION=1.22.3
    export TF_VAR_volume_source="../packer-templates/output/kubernetes/debian-11.1-amd64-qemu/debian-11.1-amd64.qcow2"
    # wrapper for docker image build, terraform apply, ansible playbook in ./ansible, applying manifests from ./manifests directory, applying terraform helm
    bash ./main.sh up
  

## Manage nodes

Get help on available commands

    bash ./main.sh help


Run ansible from the hypervisor

    bash ./main.sh ansible -m shell -a 'hostname; uname -a' all


Run other playbooks from ./ansible

    bash ./main.sh ansible_play <playbook>


Edit the variable `inventory` in ./terraform/terraform.tfvars for additional nodes with either cpn or node roles and join them

    bash ./main.sh tf apply -auto-approve
    bash ./main.sh ansible_play playbook_join_cpn.yml
    bash ./main.sh ansible_play playbook_join_node.yml


Look at inventory

    bash ./main.sh tf output


Login via ssh

    # username:password <-> provision:provision
    ssh -i ./id_ansible provision@172.31.254.2


Apply manifests from ./manifests

    bash ./main.sh manifests


Run kubectl commands from the hypervisor

    bash ./main.sh kubectl get nodes -o wide



Rebuild the docker image

    bash ./main.sh build


## Modifications

* changing the terraform files in either ./terraform or ./tf_helm requires one to remove the docker volume and rebuild the image.
* ./ansible or ./manifests are readonly mounted and can be changed without rebuilds


## Test service

Run on the hypervisor

    $ curl -v -H 'Host: whoami.k8.local' http://172.31.254.2
    * Uses proxy env variable no_proxy == 'localhost,127.0.0.1,localaddress,.localdomain.com'
    *   Trying 172.31.254.2:80...
    * Connected to 172.31.254.2 (172.31.254.2) port 80 (#0)
    > GET / HTTP/1.1
    > Host: whoami.k8.local
    > User-Agent: curl/7.80.0
    > Accept: */*
    >
    * Mark bundle as not supporting multiuse
    < HTTP/1.1 200 OK
    < Content-Length: 396
    < Content-Type: text/plain; charset=utf-8
    < Date: Sun, 14 Nov 2021 20:20:44 GMT
    <
    Hostname: whoami-7d666f84d8-dgvdq
    IP: 127.0.0.1
    IP: 192.168.115.200
    RemoteAddr: 192.168.158.129:37196
    GET / HTTP/1.1
    Host: whoami.k8.local
    User-Agent: curl/7.80.0
    Accept: */*
    Accept-Encoding: gzip
    X-Forwarded-For: 172.31.254.3
    X-Forwarded-Host: whoami.k8.local
    X-Forwarded-Port: 80
    X-Forwarded-Proto: http
    X-Forwarded-Server: traefik-ingress-controller-dp7x6
    X-Real-Ip: 172.31.254.3


From any node

    $ bash main.sh ansible -m shell -a "curl -s -H 'Host: whoami.k8.local' http://172.31.254.2" all
    + export ANSIBLE_HOST_KEY_CHECKING=False
    + ANSIBLE_HOST_KEY_CHECKING=False
    + cd ./ansible
    + ansible --inventory ../terraform/inventory --extra-vars ansible_remote_tmp=/tmp/ansible --user provision --private-key ../terraform/id_ansible --become -m shell -a 'curl -s -H '\''Host: whoami.k8.local'\'' http://172.31.254.2' all
    [WARNING]: Consider using the get_url or uri module rather than running 'curl'.
    If you need to use command because get_url or uri is insufficient you can add
    'warn: false' to this command task or set 'command_warnings=False' in
    ansible.cfg to get rid of this message.
    k8-node-3 | CHANGED | rc=0 >>
    Hostname: whoami-7d666f84d8-n7c2d
    IP: 127.0.0.1
    IP: 192.168.115.201
    RemoteAddr: 192.168.158.129:59656
    GET / HTTP/1.1
    Host: whoami.k8.local
    User-Agent: curl/7.74.0
    Accept: */*
    Accept-Encoding: gzip
    X-Forwarded-For: 172.31.254.3
    X-Forwarded-Host: whoami.k8.local
    X-Forwarded-Port: 80
    X-Forwarded-Proto: http
    X-Forwarded-Server: traefik-ingress-controller-dp7x6
    X-Real-Ip: 172.31.254.3
    k8-node-4 | CHANGED | rc=0 >>
    Hostname: whoami-7d666f84d8-dgvdq
    IP: 127.0.0.1
    IP: 192.168.115.200
    RemoteAddr: 192.168.115.202:56154
    GET / HTTP/1.1
    Host: whoami.k8.local
    User-Agent: curl/7.74.0
    Accept: */*
    Accept-Encoding: gzip
    X-Forwarded-For: 172.31.254.3
    X-Forwarded-Host: whoami.k8.local
    X-Forwarded-Port: 80
    X-Forwarded-Proto: http
    X-Forwarded-Server: traefik-ingress-controller-pmfnf
    X-Real-Ip: 172.31.254.3
    k8-node-2 | CHANGED | rc=0 >>
    Hostname: whoami-7d666f84d8-n7c2d
    IP: 127.0.0.1
    IP: 192.168.115.201
    RemoteAddr: 192.168.64.1:60760
    GET / HTTP/1.1
    Host: whoami.k8.local
    User-Agent: curl/7.74.0
    Accept: */*
    Accept-Encoding: gzip
    X-Forwarded-For: 172.31.254.3
    X-Forwarded-Host: whoami.k8.local
    X-Forwarded-Port: 80
    X-Forwarded-Proto: http
    X-Forwarded-Server: traefik-ingress-controller-wrfl6
    X-Real-Ip: 172.31.254.3
    k8-node-1 | CHANGED | rc=0 >>
    Hostname: whoami-7d666f84d8-n7c2d
    IP: 127.0.0.1
    IP: 192.168.115.201
    RemoteAddr: 192.168.115.202:50376
    GET / HTTP/1.1
    Host: whoami.k8.local
    User-Agent: curl/7.74.0
    Accept: */*
    Accept-Encoding: gzip
    X-Forwarded-For: 172.31.254.3
    X-Forwarded-Host: whoami.k8.local
    X-Forwarded-Port: 80
    X-Forwarded-Proto: http
    X-Forwarded-Server: traefik-ingress-controller-pmfnf
    X-Real-Ip: 172.31.254.3


## Cleanup

Destroy infrastructure, remove docker volume with the current state

    bash ./main.sh down

