
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

### But I don't like configuring things!
So, it appears there are ~~monsters~~ people out there who don't like the idea of managing config files, and that's fine. The reason for making this section is to provide some examples of how you can configure and work with `ssh` to hopefully achieve the minimal configuration dream. I have made some amendments to the python script included with `ssh-ssm.sh` and renamed it to `ssm-tool.py` to cater for this. It is required that both scripts are placed in `~/bin/`.

**Note**: The changes made to `ssh-ssm.sh` should not affect existing script functionality.

Goals:
- Can ssh into our instance using `Name` tag `Value`
- Can ssh into our instance using `InstanceId`
- We want minimal or zero pre-configuration required

To achieve this we can either execute `ssh-ssm.sh` directly using either the instance `Name` value or `InstanceId`:
```
[elpy@testbox ~]$ AWS_PROFILE=home python3 ~/bin/ssm-tool.py --linux --tag Name:jenkins*
instance id           |ip                    |agent up-to-date      |platform              |names
------------------------------------------------------------------------------------------------------------------
i-0xxxxxxxxxxxxx67a   |10.xx.x.x53           |True                  |CentOS Linux          |jenkins-dev-slave-autoscale01
i-0xxxxxxxxxxxxxfe9   |10.xx.x.x43           |True                  |CentOS Linux          |jenkins-dev-master-autoscale01

[elpy@testbox ~]$ AWS_PROFILE=home ~/bin/ssh-ssm.sh jenkins-dev-master-autoscale01 centos
Last login: Sun Feb 23 12:39:40 2020 from localhost
[centos@ip-10-xx-x-x43 ~]$ logout
Connection to jenkins-dev-master-autoscale01 closed.
```
or
```
[elpy@testbox ~]$ ~/bin/ssm-tool.py --profile home --tag Name:*slave* --linux
instance id           |ip                    |agent up-to-date      |platform              |names
------------------------------------------------------------------------------------------------------------------
i-0xxxxxxxxxxxxx67a   |10.xx.x.x53           |True                  |CentOS Linux          |jenkins-dev-slave-autoscale01

[elpy@testbox ~]$ AWS_PROFILE=home ~/bin/ssh-ssm.sh i-0xxxxxxxxxxxxx67a centos
Last login: Sat Feb 22 05:57:15 2020 from localhost
[centos@ip-10-xx-x-x53 ~]$ logout
Connection to i-0xxxxxxxxxxxxx67a closed.
```
No pre-configuration is required.

Alternatively, we can add each instance to our `~/.ssh/config` so that we can use `ssh` directly. It is not required for you to pre-configure your AWS profile if you're happy to specify it or switch to it each time you use `ssh`.

Example `~/.ssh/config`:
```
Host jenkins-dev* instance1 instance3 instance6
  ProxyCommand ~/bin/ssh-ssm.sh %h %r

...

Match host i-*
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/ssm-ssh-tmp
  PasswordAuthentication no
  GSSAPIAuthentication no
  ProxyCommand ~/bin/ssh-ssm.sh %h %r
```

This would enable you to ssh to instances with names: `instance1`, `instance3`, `instance6` and any instance beginning with name `jenkins-dev`. Keep in mind you need to specify the AWS profile and the `User` as we have not pre-configured it. Example below.

SSH:
```
[elpy@testbox ~]$ AWS_PROFILE=home ssh centos@jenkins-dev-slave-autoscale01
Last login: Mon Feb 24 03:45:15 2020 from localhost
[centos@ip-10-xx-x-x53 ~]$ logout
Connection to i-0xxxxxxxxxxxxx67a closed.
```

A different approach you could take (with even less pre-configuration required) is to prepend ALL `ssh` commands to SSM instances with `ssm.`, see below.

Example `~/.ssh/config`:
```
Match host ssm.*
  IdentityFile ~/.ssh/ssm-ssh-tmp
  StrictHostKeyChecking no
  PasswordAuthentication no
  GSSAPIAuthentication no
  ProxyCommand ~/bin/ssh-ssm.sh %h %r
```
Once again, this requires you enter the username and specify AWS profile when using `ssh` as we have not pre-configured it. If you use the same distro and user on all instances you could add and specify `User` in the `Match` block above. Example below.

SSH:
```
[elpy1@testbox ~]$ AWS_PROFILE=atlassian-prod ssh ec2-user@ssm.confluence-autoscale-02
Last login: Sat Feb 15 06:57:02 2020 from localhost

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
[ec2-user@ip-10-xx-x-x06 ~]$ logout
Connection to ssm.confluence-autoscale-02 closed.

```

Maybe others have come up with other cool ways to utilise SSH and AWS SSM. Feel free to reach out and/or contribute with ideas!

