#!/usr/bin/env bash
set -o nounset -o pipefail

if ! type session-manager-plugin &>/dev/null; then
cat <<EOF && exit 1
  Error! Unable to find session-manager-plugin. See:
  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
EOF
fi

[[ "$#" -ne 2 ]] && printf "  Usage: ${0} <instance-id|instance-name> <ssh user>\n" && exit 1
[[ -z "${AWS_PROFILE:-}" ]] && printf "  AWS_PROFILE not set!\n" && exit 1

if [[ "$(ps -o comm= -p $PPID)" != "ssh" ]]; then
  ssh -o IdentityFile="~/.ssh/ssm-ssh-tmp" -o ProxyCommand="${0} ${1} ${2}" ${2}@${1}
  exit 0
fi

[[ "$1" =~ ^i-([0-9a-f]{8,})$ ]] && iid="$1" ||iid=$(python3 ~/bin/ssm-tool.py --iid --tag Name:"${1}")
[[ $? -ne 0 ]] && printf "  ERROR: could not determine instance-id with provided argument!\n" && exit 1

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
  --instance-ids "$iid" \
  --document-name 'AWS-RunShellScript' \
  --parameters commands="\"
    u=\$(getent passwd ${ssh_user}) && x=\$(echo \$u |cut -d: -f6) || exit 1
    grep '${ssh_pubkey}' \${x}/${ssh_authkeys} && exit 1
    printf '${ssh_pubkey}'|tee -a \${x}/${ssh_authkeys} && sleep 15
    sed -i s,'${ssh_pubkey}',, \${x}/${ssh_authkeys}
    \"" \
  --comment "temporary ssm ssh access" #--debug

aws ssm start-session --document-name AWS-StartSSHSession --target "$iid" #--debug
