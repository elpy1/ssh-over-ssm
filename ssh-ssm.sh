#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

function main {
  local ssh_pubkey ssm_cmd
  local ssh_authkeys='.ssh/authorized_keys'
  ssh_dir=~/.ssh

  checks "$@" && ssh_pubkey=$(ssh-add -L 2>/dev/null| head -1) || mktmpkey
  ssm_cmd=$(cat <<EOF
    "u=\$(getent passwd ${2}) && x=\$(echo \$u |cut -d: -f6) || exit 1
    install -d -m700 -o${2} \${x}/.ssh; grep '${ssh_pubkey}' \${x}/${ssh_authkeys} && exit 1
    printf '${ssh_pubkey}'|tee -a \${x}/${ssh_authkeys} && sleep 15
    sed -i s,'${ssh_pubkey}',, \${x}/${ssh_authkeys}"
EOF
  )

  # put our public key on the remote server
  aws ssm send-command \
    --instance-ids "$1" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="${ssm_cmd}" \
    --comment "temporary ssm ssh access" #--debug

  # start ssh session over ssm
  aws ssm start-session --document-name AWS-StartSSHSession --target "$1" #--debug
}

function checks {
  [[ $# -ne 2 ]] && die "Usage: ${0##*/} <instance-id> <ssh user>"
  [[ ! $1 =~ ^i-([0-9a-f]{8,})$ ]] && die "ERROR: invalid instance-id"
  if [[ $(basename -- $(ps -o comm= -p $PPID)) != "ssh" ]]; then
    ssh -o IdentityFile="~/.ssh/ssm-ssh-tmp" -o ProxyCommand="${0} ${1} ${2}" "${2}@${1}"
    exit 0
  fi
  pr="$(grep -sl --exclude='*tool-env' "$1" "${ssh_dir}"/ssmtool-*)" &&
  export AWS_PROFILE=${AWS_PROFILE:-${pr##*ssmtool-}}
}

function mktmpkey {
  trap cleanup EXIT
  ssh-keygen -t ed25519 -N '' -f "${ssh_dir}"/ssm-ssh-tmp -C ssm-ssh-session
  ssh_pubkey="$(< "${ssh_dir}"/ssm-ssh-tmp.pub)"
}

function cleanup { rm -f "${ssh_dir}"/ssm-ssh-tmp{,.pub}; }
function die { echo "[${0##*/}] $*" >&2; exit 1; }

main "$@"
