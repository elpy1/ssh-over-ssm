#!/usr/bin/env python3
import boto3
import sys

def get_ec2_name(iid):
    ec2i = ec2.Instance(iid)
    iname = ''
    for tag in ec2i.tags:
        if tag['Key'] == 'Name':
            iname = tag['Value']
    return iname

def ssm_update_agent(iidlist):
    resp = ssm.send_command(
        InstanceIds=iidlist,
        DocumentName='AWS-UpdateSSMAgent',
        DocumentVersion='$LATEST')
    if resp['ResponseMetadata']['HTTPStatusCode'] == 200:
        print('success')

def ssm_list_instances():
    ssmi = ssm.describe_instance_information()['InstanceInformationList']
    names = []
    instances = []
    ips = []
    updates = []
    versions = []
    for x in ssmi:
        names.append(get_ec2_name(x['InstanceId']))
        instances.append(x['InstanceId'])
        ips.append(x['IPAddress'])
        updates.append(x['IsLatestVersion'])
        versions.append(x['PlatformName'])
    titles = ['instance id', 'ip', 'agent up-to-date', 'platform', 'name']
    data = [titles] + list(zip(instances, ips, updates, versions, names))
    return data

ec2 = boto3.resource('ec2')
ssm = boto3.client('ssm')

data = ssm_list_instances()

if not sys.argv[1:]:
    for i, d in enumerate(data):
        line = '|'.join(str(x).ljust(22) for x in d)
        print(line)
        if i == 0:
            print('-' * len(line))
elif sys.argv[1].lower() == 'update':
    iidlist = []
    for x in data[1:]:
        iidlist.append(x[0])
    ssm_update_agent(iidlist)
else:
    print('Unknown argument')
    sys.exit()
