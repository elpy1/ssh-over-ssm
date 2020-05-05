
# ssh-over-ssm
Configure SSH and use AWS SSM to connect to instances. Consider git-managing your configs for quick setup and keeping users up-to-date and in sync.

## Info and requirements
Recently I was required to administer AWS instances via Session Manager. After downloading the required plugin and initiating a SSM session locally using `aws ssm start-session` I found myself in a situation where I couldn't easily copy a file from my machine to the server (e.g. SCP, sftp, rsync etc). After some reading of AWS documentation I found it's possible to connect via SSH over SSM, solving this issue. You also get all the other benefits and functionality of SSH e.g. encryption, proxy jumping, port forwarding, socks etc.

At first I really wasn't too keen on SSM but now I'm an advocate! Some cool features:

- You can connect to your private instances inside your VPC without jumping through a public-facing bastion or instance
- You don't need to store any SSH keys locally or on the server.
- Users only require necessary IAM permissions and ability to reach their regional SSM endpoint (via HTTPS).
- SSM 'Documents' available to restrict users to specific tasks e.g. `AWS-PasswordReset` and` AWS-StartPortForwardingSession`.
- Due to the way SSM works it's unlikely to find yourself blocked by network-level security, making it a great choice if you need to get out to the internet from inside a restrictive network :p

### Requirements
- Instances must have access to ssm.{region}.amazonaws.com
- IAM instance profile allowing SSM access must be attached to EC2 instance
- SSM agent must be installed on EC2 instance
- AWS cli requires you install `session-manager-plugin` locally

Existing instances with SSM agent already installed may require agent updates.

## How it works
You configure each of your instances in your SSH config and specify `ssh-ssm.sh` to be executed as a `ProxyCommand` with your `AWS_PROFILE` environment variable set.
If your key is available via ssh-agent it will be used by the script, otherwise a temporary key will be created, used and destroyed on termination of the script. The public key is copied across to the instance using `aws ssm send-command` and then the SSH session is initiated through SSM using `aws ssm start-session` (with document `AWS-StartSSHSession`) after which the SSH connection is made. The public key copied to the server is removed after 15 seconds and provides enough time for SSH authentication.

## Installation and Usage
This tool is intended to be used in conjunction with `ssh`. It requires that you've configured your awscli (`~/.aws/{config,credentials}`) properly and you spend a small amount of time planning and updating your ssh config.

### Listing and updating SSM instances
First, we need to make sure the agent on each of our instances is up-to-date. You can use `aws ssm describe-instance-information` to list instances and `aws ssm send-command` to update them. Alternatively, I've included a small python script to quickly list or update your instances:

Check your instances
```
[elpy@testbox ~]$ AWS_PROFILE=int-monitor1 python3 ssm-tool.py
instance id           |ip                    |agent up-to-date      |platform              |name
------------------------------------------------------------------------------------------------------------------
i-0xxxxxxxxxxxxx3b4   |10.xx.xx.6            |False                 |Ubuntu                |instance1
i-0xxxxxxxxxxxxx76e   |10.xx.xx.142          |False                 |Ubuntu                |instance2
i-0xxxxxxxxxxxxx1b6   |10.xx.xx.75           |False                 |Ubuntu                |instance3
i-0xxxxxxxxxxxxxac8   |10.xx.xx.240          |False                 |Ubuntu                |instance4
i-0xxxxxxxxxxxxxb1a   |10.xx.xx.206          |False                 |Ubuntu                |instance5
i-0xxxxxxxxxxxxx504   |10.xx.xx.84           |False                 |Amazon Linux          |
i-0xxxxxxxxxxxxx73d   |10.xx.xx.48           |False                 |Ubuntu                |instance6
i-0xxxxxxxxxxxxxd56   |10.xx.xx.201          |False                 |Ubuntu                |instance7
i-0xxxxxxxxxxxxxfe9   |10.xx.xx.143          |False                 |CentOS Linux          |instance8
i-0xxxxxxxxxxxxxb8e   |10.xx.xx.195          |False                 |Ubuntu                |instance9

```

Update all instances
```
[elpy@testbox ~]$ AWS_PROFILE=int-monitor1 python3 ssm-tool.py --update
success

[elpy@testbox ~]$ AWS_PROFILE=int-monitor1 python3 ssm-tool.py
instance id           |ip                    |agent up-to-date      |platform              |name
------------------------------------------------------------------------------------------------------------------
i-0xxxxxxxxxxxxx3b4   |10.xx.xx.6            |True                 |Ubuntu                |instance1
i-0xxxxxxxxxxxxx76e   |10.xx.xx.142          |True                 |Ubuntu                |instance2
i-0xxxxxxxxxxxxx1b6   |10.xx.xx.75           |True                 |Ubuntu                |instance3
i-0xxxxxxxxxxxxxac8   |10.xx.xx.240          |True                 |Ubuntu                |instance4
i-0xxxxxxxxxxxxxb1a   |10.xx.xx.206          |True                 |Ubuntu                |instance5
i-0xxxxxxxxxxxxx504   |10.xx.xx.84           |True                 |Amazon Linux          |
i-0xxxxxxxxxxxxx73d   |10.xx.xx.48           |True                 |Ubuntu                |instance6
i-0xxxxxxxxxxxxxd56   |10.xx.xx.201          |True                 |Ubuntu                |instance7
i-0xxxxxxxxxxxxxfe9   |10.xx.xx.143          |True                 |CentOS Linux          |instance8
i-0xxxxxxxxxxxxxb8e   |10.xx.xx.195          |True                 |Ubuntu                |instance9
```

### SSH config

Now that all of our instances are running an up-to-date agent we need to update our SSH config.

Example of basic `~/.ssh/config`:
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
  PasswordAuthentication no
  GSSAPIAuthentication no
```
Above we've configured 3 separate instances for SSH access over SSM, specifying the username, instance ID and host to use for local commands i.e. `ssh {host}`. We also set our `AWS_PROFILE` as per awscli configuration. If you only have a few instances to configure this might be OK to work with, but when you've got a large number of instances and different AWS profiles (think: work-internal, work-clients, personal) you're bound to end up with a huge config file and lots of repetition. I've taken a slightly different approach by splitting up my config into fragments and using ssh config directive `Include`. It is currently set up similar to below.

Example `~/.ssh/config`:
```
Host *
  Include conf.d/internal/*
  Include conf.d/clients/*
  Include conf.d/personal/*
  KeepAlive yes
  Protocol 2
  ServerAliveInterval 30
  ConnectTimeout 10

Match exec "find ~/.ssh/conf.d -type f -name '*_ssm' -exec grep '%h' {} +"
  IdentityFile ~/.ssh/ssm-ssh-tmp
  PasswordAuthentication no
  GSSAPIAuthentication no
```

Example `~/.ssh/conf.d/personal/atlassian-prod_ssm`:
```
Host confluence-prod.personal
  Hostname i-0xxxxxxxxxxxxxe28

Host jira-prod.personal
  Hostname i-0xxxxxxxxxxxxxe49

Host bitbucket-prod.personal
  Hostname i-0xxxxxxxxxxxxx835

Match host i-*
  User ec2-user
  ProxyCommand bash -c "AWS_PROFILE=atlassian-prod ~/bin/ssh-ssm.sh %h %r"
```

All SSM hosts are saved in a fragment ending in '\_ssm'. Within the config fragment I include each instance, their corresponding hostname (instance ID) and a `Match` directive containing the relevant `User` and `ProxyCommand`. This approach is not required but I personally find it neater and better for management.

### Testing/debugging SSH connections

Show which config file and `Host` you match against and the final command executed by SSH:
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

Once you've tested it and you're confident it's all correct give it a go! Remember to place `ssh-ssm.sh` in `~/bin/` (or wherever you prefer).

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
[elpy@testbox ~]$ ssh -f -nNT -D 8080 jira-prod.personal
[elpy@testbox ~]$ curl -x socks://localhost:8080 ipinfo.io/ip
54.xxx.xxx.49
[elpy@testbox ~]$ whois 54.xxx.xxx.49 | grep -i techname
OrgTechName:   Amazon EC2 Network Operations
```

DB tunnel:
```
[elpy@testbox ~]$ ssh -f -nNT -oExitOnForwardFailure=yes -L 5432:db1.host.internal:5432 jira-prod.personal
[elpy@testbox ~]$ ss -lt4p sport = :5432
State      Recv-Q Send-Q Local Address:Port                 Peer Address:Port
LISTEN     0      128       127.0.0.1:postgres                        *:*                     users:(("ssh",pid=26130,fd=6))
[elpy@testbox ~]$ psql --host localhost --port 5432
Password:
```

