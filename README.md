# ssh-over-ssm
Configure SSH and use AWS SSM to connect to instances. Consider git-managing your configs for quick setup and keeping users up-to-date and in sync.

**NOTE:** [ssm-tool](https://github.com/elpy1/ssm-tool) has been moved to its own repo.

## Getting started
Recently I was required to administer AWS instances via Session Manager. After downloading the required plugin and initiating a SSM session locally using `aws ssm start-session` I found myself in a situation where I couldn't easily copy
a file from my machine to the server (e.g. using `scp`, `sftp`, `rsync` etc). After some reading of the AWS documentation I discovered it's possible to connect via SSH over SSM, solving this issue. You also get all the other benefits and functionality of SSH e.g. encryption, proxy jumping, port forwarding, socks etc.

At first I really wasn't too keen on SSM but now I'm an advocate! Some cool features:
- You can connect to your private instances inside your VPC without jumping through a public-facing bastion or instance
- You don't need to store any SSH keys locally or on the server.
- Users only require necessary IAM permissions and ability to reach their regional SSM endpoint (via HTTPS).
- SSM 'Documents' are available to restrict users to specific tasks e.g. `AWS-PasswordReset` or `AWS-StartPortForwardingSession`.
- Due to the way SSM works it's unlikely to find yourself blocked by network-level security, making it a great choice if you need to get out to the internet from inside a restrictive network :p

## Requirements
- Instances must have access to ssm.`{region}`.amazonaws.com
- IAM instance profile allowing SSM access must be attached to EC2 instance
- SSM agent must be installed on EC2 instance
- AWS cli requires you install `session-manager-plugin` locally

Existing instances with SSM agent already installed may require agent updates.

## How it works
`ssh-ssm.sh` is a small bash script that performs some checks on execution and then runs two AWS commands:
- `aws ssm send-command` (with SSM document `AWS-RunShellScript`)
- `aws ssm start-session` (with SSM document `AWS-StartSSHSession`)

This allows you to connect via SSH to instances over SSM without needing to manage SSH keys on remote servers.

The difference between this and the `ProxyCommand` recommended in the [AWS documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html) is `ssh-ssm.sh` automates placing your local SSH public key on the remote server prior to initiating the SSH connection. Without this step your public key must exist on the server (under the correct user's directory) before you connect.

The public key copied to the remote server is removed automatically after 15 seconds, allowing enough time for SSH authentication.

## Installation and Usage
This tool is intended to be used in conjunction with `ssh`. It requires that you've configured your AWS CLI (`~/.aws/{config,credentials}`) properly. You can either use it as a replacement for the standard AWS `ProxyCommand` or spend some time planning and updating your SSH config.

### Listing and updating SSM instances
First, we need to make sure the agent on each of our instances is up-to-date. You can use `aws ssm describe-instance-information` to list instances and `aws ssm send-command` to update them. Alternatively, use [ssm-tool](https://github.com/elpy1/ssm-tool) to list or update your instances:

Check your instances
```
[elpy@testbox ~]$ AWS_PROFILE=int-monitor1 python3 ssm-tool
instance id           |ip                    |agent up-to-date      |platform              |name
------------------------------------------------------------------------------------------------------------------
i-0xxxxxxxxxxxxx3b4   |10.xx.xx.6            |False                 |Ubuntu                |instance1
i-0xxxxxxxxxxxxx504   |10.xx.xx.84           |False                 |Amazon Linux          |
i-0xxxxxxxxxxxxxfe9   |10.xx.xx.143          |False                 |CentOS Linux          |instance8

```

Update all instances
```
[elpy@testbox ~]$ AWS_PROFILE=int-monitor1 python3 ssm-tool --update
success

[elpy@testbox ~]$ AWS_PROFILE=int-monitor1 python3 ssm-tool.py
instance id           |ip                    |agent up-to-date      |platform              |name
------------------------------------------------------------------------------------------------------------------
i-0xxxxxxxxxxxxx3b4   |10.xx.xx.6            |True                 |Ubuntu                |instance1
i-0xxxxxxxxxxxxx504   |10.xx.xx.84           |True                 |Amazon Linux          |
i-0xxxxxxxxxxxxxfe9   |10.xx.xx.143          |True                 |CentOS Linux          |instance8
```

### SSH configuration

Now that all of our instances are running an up-to-date agent we need to update our SSH config (`~/.ssh/config`).

#### The minimum required
```
# applies to all hosts and ensures our SSH sessions remain alive when idle
Host *
  TCPKeepAlive yes
  ServerAliveInterval 30
  ConnectTimeout 10

#------
# place any other/existing configuration here
#------

Match Host i-*
  ProxyCommand ssh-ssm.sh %h %r
  IdentityFile ~/.ssh/ssm-ssh-tmp
  StrictHostKeyChecking no
  BatchMode yes
```
This enables you to connect via `ssh` using the appropriate username and instance-id e.g. `ssh ec2-user@<instance-id>`. You'll need to ensure AWS credentials are available in your environment, either with `AWS_PROFILE` or `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`.

#### Basic configuration example
```
Host confluence-prod.personal
  Hostname i-0xxxxxxxxxxxxxe28
  User ec2-user
  ProxyCommand bash -c "AWS_PROFILE=atlassian-prod ~/bin/ssh-ssm.sh %h %r"

Host jira-stg.personal
  Hostname i-0xxxxxxxxxxxxxe49
  User ec2-user
  ProxyCommand bash -c "AWS_PROFILE=atlassian-nonprod ~/bin/ssh-ssm.sh %h %r"

Host jenkins-master.personal
  Hostname i-0xxxxxxxxxxxxx143
  User centos
  ProxyCommand bash -c "AWS_PROFILE=jenkins-home ~/bin/ssh-ssm.sh %h %r"

Match Host i-*
  IdentityFile ~/.ssh/ssm-ssh-tmp
  BatchMode yes
```

Above we've configured 3 separate instances for SSH access by specifying the username, instance-id and host to use for local commands i.e. `ssh {host}`. We've also hard-coded the `AWS_PROFILE` environment variable for the `ProxyCommand`
so we don't need to manually provide credentials via tooling. This type of configuration is generally OK if you only have a few instances to work with.

### Testing/debugging SSH connections

Show which config file and `Host` you match against, and the final command executed by SSH:
```
ssh -G confluence-prod.personal
```

Debug connection issues:
```
ssh -vvv user@host
```

For further informaton consider enabling debug for `aws` (edit ssh-ssm.sh):
```
aws ssm --debug command
```

Once you've tested it and you're confident it's all correct give it a go! Remember to place `ssh-ssm.sh` in `~/bin/` (or wherever you prefer), and ensure it's available in your `$PATH`.

### Example usage
SSH:
```
[elpy1@testbox ~]$ aws-mfa
INFO - Validating credentials for profile: default
INFO - Your credentials are still valid for 14105.807801 seconds they will expire at 2020-01-25 18:06:08
[elpy1@testbox ~]$ ssh confluence-prod.personal
Last login: Sat Jan 25 08:59:40 2020 from localhost

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
[ec2-user@ip-10-xx-x-x06 ~]$ logout
Connection to i-0fxxxxxxxxxxxxe28 closed.
```

SCP:
```
[elpy@testbox ~]$ scp ~/bin/ssh-ssm.sh bitbucket-prod.personal:~
ssh-ssm.sh                                                                                       100%  366    49.4KB/s   00:00

[elpy@testbox ~]$ ssh bitbucket-prod.personal ls -la ssh\*
-rwxrwxr-x 1 ec2-user ec2-user 366 Jan 26 07:27 ssh-ssm.sh
```

SOCKS:
```
[elpy@testbox ~]$ ssh -f -NT -D 8080 jira-prod.personal
[elpy@testbox ~]$ curl -x socks://localhost:8080 ipinfo.io/ip
54.xxx.xxx.49
[elpy@testbox ~]$ whois 54.xxx.xxx.49 | grep -i techname
OrgTechName:   Amazon EC2 Network Operations
```

DB tunnel:
```
[elpy@testbox ~]$ ssh -f -NT -oExitOnForwardFailure=yes -L 5432:db1.host.internal:5432 jira-prod.personal
[elpy@testbox ~]$ ss -lt4p sport = :5432
State      Recv-Q Send-Q Local Address:Port                 Peer Address:Port
LISTEN     0      128       127.0.0.1:postgres                        *:*                     users:(("ssh",pid=26130,fd=6))
[elpy@testbox ~]$ psql --host localhost --port 5432
Password:
```

SSH (with minimum required configuration):
```
[elpy@testbox ~]$ jumpbox=$(aws --profile atlassian-prod ec2 describe-instances --filters 'Name=tag:Name,Values=confluence-prod' --output text --query 'Reservations[*].Instances[*].InstanceId')
[elpy@testbox ~]$ echo ${jumpbox}
i-0fxxxxxxxxxxxxe28
[elpy@testbox ~]$ AWS_PROFILE=atlassian-prod ssh ec2-user@${jumpbox}
Last login: Sat Jan 25 08:59:40 2020 from localhost

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
[ec2-user@ip-10-xx-x-x06 ~]$ logout
Connection to i-0fxxxxxxxxxxxxe28 closed.
```
