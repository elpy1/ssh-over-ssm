#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

SSH_DIR=$HOME/.ssh
SSH_TMP_KEY=${SSH_DIR}/ssm-ssh-tmp

die () { echo "[${0##*/}] $*" >&2; exit 1; }
make_ssh_keys () { ssh-keygen -t rsa -N '' -f ${SSH_TMP_KEY} -C ssh-over-ssm; }
clean_ssh_keys () { rm -f ${SSH_TMP_KEY}{,.pub}; }

[[ $# -ne 2 ]] && die "usage: ${0##*/} <instance-id> <ssh user>"
[[ ! $1 =~ ^i-([0-9a-f]{8,})$ ]] && die "error: invalid instance-id"

if [[ $(basename -- $(ps -o comm= -p $PPID)) != "ssh" ]]; then
  exec ssh -o IdentityFile="${SSH_TMP_KEY}" -o ProxyCommand="$0 $1 $2" "$2@$1"
elif pr="$(grep -sl --exclude='*-env' "$1" ${SSH_DIR}/ssmtool-*)"; then
  export AWS_PROFILE=${AWS_PROFILE:-${pr##*ssmtool-}}
fi

# get ssh key from agent or generate a temp key
if ssh-add -l >/dev/null 2>&1; then
  SSH_PUB_KEY="$(ssh-add -L |head -1)"
else
  [[ -f ${SSH_TMP_KEY}.pub ]] || make_ssh_keys
  trap clean_ssh_keys EXIT
  SSH_PUB_KEY="$(< ${SSH_TMP_KEY}.pub)"
fi

# command to put our public key on the remote server (user must already exist)
ssm_cmd=$(cat <<EOF
  "sudo useradd ssm-user; echo ssm-user ALL=\\(ALL\\) NOPASSWD:ALL | sudo tee /etc/sudoers.d/ssm-agent-users;
  u=\$(getent passwd ${2}) && x=\$(echo \$u |cut -d: -f6) || exit 1
  [ ! -d \${x}/.ssh ] && install -d -m700 -o${2} \${x}/.ssh
  grep '${SSH_PUB_KEY}' \${x}/.ssh/authorized_keys && exit 0
  printf '${SSH_PUB_KEY}\n'|tee -a \${x}/.ssh/authorized_keys || exit 1
  (sleep 15 && sed -i '\|${SSH_PUB_KEY}|d' \${x}/.ssh/authorized_keys &) >/dev/null 2>&1"
EOF
)

# execute the command using aws ssm send-command
command_id=$(aws ssm send-command \
  --instance-ids "$1" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="${ssm_cmd}" \
  --comment "temporary ssm ssh access" \
  --output text \
  --query Command.CommandId)

# wait for successful send-command execution
aws ssm wait command-executed --instance-id "$1" --command-id "${command_id}"

# start ssh session over ssm
aws ssm start-session --document-name AWS-StartSSHSession --target "$1"
