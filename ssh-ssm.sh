#!/usr/bin/env bash
set -o nounset -o pipefail

if ! type session-manager-plugin &>/dev/null; then
cat <<EOF && exit 1
  Error! Unable to find session-manager-plugin. See:
  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
EOF
fi

[[ "$#" -ne 2 ]] && printf "  Usage: ${0} <instance-id> <ssh user>\n" && exit 1
[[ -z "${AWS_PROFILE:-}" ]] && printf "  AWS_PROFILE not set!\n" && exit 1
[[ "$(ps -o comm= -p $PPID)" != "ssh" ]] && { cat && exit 1; } <<EOF
  This script must be invoked by ssh to work correctly.
  To run manually use:
  AWS_PROFILE=${AWS_PROFILE} ssh -o IdentityFile="~/.ssh/ssm-ssh-tmp" -o ProxyCommand="${0} ${1} ${2}" ${2}@${1}
EOF

function cleanup {
  rm -f "${ssh_local}"/ssm-ssh-tmp{,.pub}
}

function tempkey {
  set -o errexit
  trap cleanup EXIT
  ssh-keygen -t ed25519 -N '' -f "${ssh_local}"/ssm-ssh-tmp -C ssm-ssh-session
  ssh_pubkey=$(< "${ssh_local}"/ssm-ssh-tmp.pub)
}

ssh_user="$2"
ssh_authkeys='.ssh/authorized_keys'
ssh_local=~/.ssh
ssh_pubkey=$(ssh-add -L 2>/dev/null| head -1) || tempkey

aws ssm send-command \
  --instance-ids "$1" \
  --document-name 'AWS-RunShellScript' \
  --parameters commands="\"
    u=\$(getent passwd ${ssh_user}) && x=\$(cut -d: -f6 <<<\$u) || exit 1
    grep '${ssh_pubkey}' \${x}/${ssh_authkeys} && exit 1
    printf '${ssh_pubkey}'|tee -a \${x}/${ssh_authkeys} && sleep 15
    sed -i s,'${ssh_pubkey}',, \${x}/${ssh_authkeys}
    \"" \
  --comment "temporary ssm ssh access" #--debug

aws ssm start-session --document-name AWS-StartSSHSession --target "$1" #--debug
