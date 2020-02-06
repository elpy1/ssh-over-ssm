#!/usr/bin/env python3
import boto3
import sys

#############################################################
## Usage:
## AWS_PROFILE=awscli-profile python3 /path/to/ssm_instances.py
## or, to update the SSM agent on all instances use:
## AWS_PROFILE=awscli-profile python3 /path/to/ssm_instances.py update
#############################################################

def get_ec2_name(iid):
    try:
        etags = ec2.Instance(iid).tags
        name = [tag['Value'] for tag in etags if tag['Key'] == 'Name']
        return name[0] if name else ''
    except Exception as e:
        print(f"ERROR: {e}")

def ssm_update_agent(iidlist):
    try:
        resp = ssm.send_command(
            InstanceIds=iidlist,
            DocumentName='AWS-UpdateSSMAgent',
            DocumentVersion='$LATEST')
        if resp['ResponseMetadata']['HTTPStatusCode'] == 200:
            print('success')
    except Exception as e:
        print(f"ERROR: {e}")

def ssm_list_instances():
    ssmi = ssm.describe_instance_information()['InstanceInformationList']
    names = [get_ec2_name(x['InstanceId']) for x in ssmi]
    instances = [x['InstanceId'] for x in ssmi]
    ips = [x['IPAddress'] for x in ssmi]
    updates = [x['IsLatestVersion'] for x in ssmi]
    versions = [x['PlatformName'] for x in ssmi]
    titles = ['instance id', 'ip', 'agent up-to-date', 'platform', 'name']
    data = [titles] + list(zip(instances, ips, updates, versions, names))
    return data

ec2 = boto3.resource('ec2')
ssm = boto3.client('ssm')
data = ssm_list_instances()

if (sys.argv[1:] and not 'update' in sys.argv[1].lower()):
    print(f"  Usage: {sys.argv[0]} or {sys.argv[0]} update")
    sys.exit()

if sys.argv[1:]:
    iidlist = [x[0] for x in data[1:]]
    ssm_update_agent(iidlist)
else:
    for i, d in enumerate(data):
        line = '|'.join(str(x).ljust(22) for x in d)
        print(line)
        if i == 0: print('-' * len(line))
