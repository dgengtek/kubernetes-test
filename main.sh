#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# 
# ------------------------------------------------------------------------------
# only use uppercase variables for environment variables 


set -u # error on unset variables or parameters
set -e # exit on unchecked errors
set -b # report status of background jobs
# set -m # monitor mode - enable job control
# set -n # read commands but do not execute
# set -p # privileged mode - constrained environment
# set -v # print shell input lines
# set -x # expand every command
set -o pipefail # fail on pipe errors
# set -C # bash does not overwrite with redirection operators

declare -i enable_verbose=0
declare -i enable_quiet=0
declare -i enable_debug=0
declare -i enable_system_log=0
readonly __script_name="${BASH_SOURCE[0]##*/}"
readonly DOCKER_IMAGE_NAME=$(basename $(dirname $(realpath -e "$0")))



usage() {
  cat >&2 << EOF
Usage: ${0##*/} [OPTIONS] <command> [<arguments>]

$(sed -n 's/^_\([^_)(]*\)() {[ ]*#\(.*\)/\1  \2/p' $__script_name | sort -k1 | column -t -N '<command>' -l 2)

OPTIONS:
  -v  verbose
  -q  quiet
EOF
}


main() {
  local -a options
  local -a args

  check_dependencies
  # parse input args 
  parse_options "$@"
  # set leftover options parsed local input args
  set -- "${args[@]}"
  # remove args array
  unset -v args
  check_input_args "$@"

  set_signal_handlers
  prepare_env
  pre_run
  run "$@"
  post_run 
  unset_signal_handlers
}


################################################################################
# script internal execution functions
################################################################################

run() {
  local command=$1
  if [[ $(type -t _${command}) == "function" ]]; then
    shift
    _${command} "$@"
  else
    exec "$@"
  fi
}


check_dependencies() {
  :
}


check_input_args() {
  if [[ -z ${1:-""} ]]; then
    usage
    exit 1
  fi
}


prepare_env() {
  set_descriptors
}


prepare() {
  export PATH_USER_LIB=${PATH_USER_LIB:-"$HOME/.local/lib/"}

  source_libs
  set_descriptors
}


source_libs() {
  source "${PATH_USER_LIB}libutils.sh"
  source "${PATH_USER_LIB}libcolors.sh"
}


set_descriptors() {
  if (($enable_verbose)); then
    exec {fdverbose}>&2
  else
    exec {fdverbose}>/dev/null
  fi
  if (($enable_debug)); then
    set -xv
    exec {fddebug}>&2
  else
    exec {fddebug}>/dev/null
  fi
}


pre_run() {
  :
}


post_run() {
  :
}


parse_options() {
  # exit if no options left
  [[ -z ${1:-""} ]] && return 0
  # log "parse \$1: $1" 2>&$fddebug

  local do_shift=0
  case $1 in
      -v|--verbose)
	enable_verbose=1
	;;
      -q|--quiet)
        enable_quiet=1
        ;;
      --enable-log)
        enable_system_log=1
        ;;
      -p|--path)
        path=$2
        do_shift=2
        ;;
      --)
        do_shift=3
        ;;
      *)
        do_shift=1
	;;
  esac
  if (($do_shift == 1)) ; then
    args+=("$1")
  elif (($do_shift == 2)) ; then
    # got option with argument
    shift
  elif (($do_shift == 3)) ; then
    # got --, use all arguments left as options for other commands
    shift
    options+=("$@")
    return
  fi
  shift
  parse_options "$@"
}


################################################################################
# signal handlers
#-------------------------------------------------------------------------------


set_signal_handlers() {
  trap sigh_abort SIGABRT
  trap sigh_alarm SIGALRM
  trap sigh_hup SIGHUP
  trap sigh_cont SIGCONT
  trap sigh_usr1 SIGUSR1
  trap sigh_usr2 SIGUSR2
  trap sigh_cleanup SIGINT SIGQUIT SIGTERM EXIT
}


unset_signal_handlers() {
  trap - SIGABRT
  trap - SIGALRM
  trap - SIGHUP
  trap - SIGCONT
  trap - SIGUSR1
  trap - SIGUSR2
  trap - SIGINT SIGQUIT SIGTERM EXIT
}


sigh_abort() {
  trap - SIGABRT
}


sigh_alarm() {
  trap - SIGALRM
}


sigh_hup() {
  trap - SIGHUP
}


sigh_cont() {
  trap - SIGCONT
}


sigh_usr1() {
  trap - SIGUSR1
}


sigh_usr2() {
  trap - SIGUSR2
}


sigh_cleanup() {
  trap - SIGINT SIGQUIT SIGTERM EXIT
  local active_jobs=$(jobs -p)
  for p in $active_jobs; do
    if [[ -e "/proc/$p" ]]; then
      kill "$p" >/dev/null 2>&1
      wait "$p"
    fi
  done
}


log() {
  local cmd=("-s" "-t $__script_name")
  (($enable_system_log)) || cmd+=("--no-act")
  logger "${cmd[*]}" "$@"
}


# generate system logging function log_* for every level
for level in emerg err warning info debug; do
  printf -v functext -- 'log_%s() { logger -p user.%s -t %s -- "$@" ; }' "$level" "$__script_name"
  eval "$functext"
done


################################################################################
# custom functions
#-------------------------------------------------------------------------------

_build () {  #build the docker image
  sudo docker build --build-arg KUBERNETES_VERSION=$KUBERNETES_VERSION -t $DOCKER_IMAGE_NAME .
}


_rm_vol() {  # remove the volumes containing the terraform state for ./terraform and ./tf_helm
  sudo docker volume rm "${DOCKER_IMAGE_NAME}_terraform"
  sudo docker volume rm "${DOCKER_IMAGE_NAME}_terraform_helm"
}


_up() {  # create, provision the cluster nodes, apply manifests and download any required files to connect to the local cluster
  _infrastructure
  _get_private_key
  _ansible_play playbook.yml
  _get_kubeconfig
  _manifests
  _tf_helm apply -auto-approve
}


_infrastructure() {  # build docker image and apply terraform in ./terraform
  _build
  _tf apply -auto-approve
}


# use manually after cluster has been already provisioned with ansible
_terraform() {  # run terraform for ./terraform and ./tf_helm
  _infrastructure
  _tf_helm apply -auto-approve
}


_get_private_key() {  # copy the ssh private key generated by terraform to connect to the cluster nodes
  _get_file id_ansible
}


_get_kubeconfig() {  # copy the admin.conf kubeconfig from volume on to your host
  _get_file admin.conf
}


_get_file() {  # get a specific file from /wd/terraform/
  local filename=${1:?Filename required}
  local -a docker_args
  set_environment

  local cid=$(sudo docker run -d \
    "${docker_args[@]}" \
    $DOCKER_IMAGE_NAME true)
  sudo docker cp ${cid}:/wd/terraform/$filename .
  sudo chmod 600 ./$filename
  sudo chown $(id -u):$(id -g) ./$filename
  sudo docker rm $cid
}


_down() {  # destroy domains, cleanup volumes and remove local cluster files
  _tf destroy -auto-approve
  _rm_vol
  rm -f ./id_ansible
  rm -f ./admin.conf
}


_tf() {  # apply terraform from ./terraform
  local -a docker_args
  set_environment

  sudo docker run --rm -i \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME" /dev/stdin "$@" <<'EOF'
set -x
cd ./terraform
terraform "$@"
EOF
}


_tf_helm() {  # apply helm with the terraform provisioner from ./tf_helm
  local -a docker_args
  set_environment

  sudo docker run --rm -i \
    --network host \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME" /dev/stdin "$@" <<'EOF'
set -x
cd ./tf_helm
terraform "$@" -var-file="../terraform/terraform.tfvars" 
EOF
}


_helm() {  # run helm manually with the kubeadm generated admin.conf kubeconfig
  local -a docker_args
  set_environment
  docker_args+=("--mount" "type=bind,source=${PWD}/helm,target=/wd/helm,readonly")

  sudo docker run --rm -i \
    --network host \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME" /dev/stdin "$@" <<'EOF'
set -x
helm "$@"
EOF
}


_kubectl() {  # run kubectl with the kubeadm generated admin.conf kubeconfig 
  local -a docker_args
  set_environment
  docker_args+=("--mount" "type=bind,source=${PWD}/manifests,target=/wd/manifests,readonly")

  sudo docker run --rm -i \
    --network host \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME" /dev/stdin "$@" <<'EOF'
set -x
kubectl "$@"
EOF
}


_manifests() {  # apply kubernetes manifests in the directory ./manifests to the cluster
  _kubectl apply -R --prune --all -f ./manifests
}


_ansible_play() {  # run ansible-playbook 
  local -a docker_args
  set_environment
  docker_args+=("--mount" "type=bind,source=${PWD}/ansible,target=/wd/ansible,readonly")

  sudo docker run --rm -i \
    --network host \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME" /dev/stdin "$@" <<'EOF'
set -x
cd ./ansible
ansible-playbook \
  --inventory ../terraform/inventory \
  --extra-vars "ansible_remote_tmp=/tmp/ansible" \
  --user provision \
  --private-key ../terraform/id_ansible \
  --become \
  "$@"
EOF
}

_ansible() {  # run ansible with the currently deployed inventory of terraform
  local -a docker_args
  set_environment
  docker_args+=("--mount" "type=bind,source=${PWD}/ansible,target=/wd/ansible,readonly")

  sudo docker run --rm -i \
    --network host \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME" /dev/stdin "$@" <<'EOF'
set -x
cd ./ansible
ansible \
  --inventory ../terraform/inventory \
  --extra-vars "ansible_remote_tmp=/tmp/ansible" \
  --user provision \
  --private-key ../terraform/id_ansible \
  --become \
  "$@"
EOF
}


_inventory() {  # display the terraform inventory
  _tf output -json | jq -r '.inventory.value[][] | (.hostname + " " + .ip + " " .role)'
}


_sh() {  # spawn a shell inside the docker container with the mounted volumes
  local -a docker_args
  set_environment
  docker_args+=("--mount" "type=bind,source=${PWD}/manifests,target=/wd/manifests,readonly")
  docker_args+=("--mount" "type=bind,source=${PWD}/ansible,target=/wd/ansible,readonly")

  sudo docker run --rm -it \
    --network host \
    "${docker_args[@]}" \
    $DOCKER_IMAGE_NAME
}

__git_clone() {
  local dir=$(basename "$1")
  test -d "$dir" && return
  git clone "$1"
}

set_environment() {
  local volume_path
  local source_name

  mkdir -p ./ansible/roles 
  ( 
    cd ./ansible/roles
    __git_clone https://github.com/dgengtek/ansible-role-docker
    __git_clone https://github.com/dgengtek/ansible-role-kubernetes
  )

  if volume_path=$(realpath -e "$TF_VAR_volume_source"); then
    volume_path=$(dirname "$volume_path")
    source_name=$(basename "$TF_VAR_volume_source")
    docker_args+=("--mount" "type=bind,source=$volume_path,target=/image")
    docker_args+=("--env" "TF_VAR_volume_source=/image/$source_name")
  else
    docker_args+=("--env" "TF_VAR_volume_source=$TF_VAR_volume_source")
  fi

  docker_args+=("--env" "ANSIBLE_HOST_KEY_CHECKING=False")
  docker_args+=("--env" "KUBECONFIG=/wd/terraform/admin.conf")
  docker_args+=("--mount" "type=bind,source=/var/run/libvirt/libvirt-sock,target=/var/run/libvirt/libvirt-sock")
  docker_args+=("--mount" "source=${DOCKER_IMAGE_NAME}_terraform,target=/wd/terraform")
  docker_args+=("--mount" "source=${DOCKER_IMAGE_NAME}_terraform_helm,target=/wd/tf_helm")
}

_help() {  # display this help
  usage
}


#-------------------------------------------------------------------------------
# end custom functions
################################################################################


prepare
main "$@"
