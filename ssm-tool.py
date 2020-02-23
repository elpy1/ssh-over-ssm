#!/usr/bin/env python3
import argparse
import boto3
import datetime
import os
import sys
from dateutil.tz import tzlocal
from boto3.session import Session


def get_profiles():
    try:
        aws_profiles = Session().available_profiles
        return aws_profiles
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

def process_args():
    parser = argparse.ArgumentParser(description='ssh-ssm toolkit')
    group = parser.add_mutually_exclusive_group()
    parser.add_argument('--profile', dest='profile', action='store', choices=get_profiles(), default=os.getenv('AWS_PROFILE') or 'default', metavar='', help='AWS profile. default is \'default\'')
    group.add_argument('-u', '--update', action='store_true', help='update ssm-agent on returned instances')
    group.add_argument('-i', '--iid', dest='iidonly', action='store_true', help='return only instance ids')
    parser.add_argument('-x', '--linux', dest='platforms', action='append_const', const='Linux', help='filter only linux machines')
    parser.add_argument('-w', '--windows', dest='platforms', action='append_const', const='Windows', help='filter only windows machines')
    parser.add_argument('-t', '--tag', dest='tag', action='store', default='Name:*', metavar='key:value', help='filter by ec2 tag. default value is \'Name:*\'')
    return parser.parse_args()


def get_ec2_name(iid):
    ec2r = session.resource('ec2')
    try:
        etags = ec2r.Instance(iid).tags
        name = [tag['Value'] for tag in etags if tag['Key'] == 'Name']
        return name[0] if name else ''
    except Exception as e:
        print(f"ERROR: {e}")


def filtered_instances(filter):
    try:
        resp = ec2.describe_instances(Filters=[filter])
        return resp['Reservations']
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


def ssm_list_instances(filter):
    try:
        ssminstances = ssm.describe_instance_information(MaxResults=50, Filters=[filter])
        ssmi = ssminstances['InstanceInformationList']
        while True:
            next_token = ssminstances.get('NextToken')
            if not next_token: break
            ssminstances = ssm.describe_instance_information(MaxResults=50, Filters=[filters], NextToken=next_token)
            ssmi.extend(ssminstances['InstanceInformationList'])
        return ssmi
    except Exception as e:
        print(f"ERROR:{e}")


def build_table(ssmi, filtered):
    names = [get_ec2_name(i.get('InstanceId')) for i in ssmi if i['InstanceId'] in filtered]
    instances = [i.get('InstanceId') for i in ssmi if i['InstanceId'] in filtered]
    ips = [i.get('IPAddress') for i in ssmi if i['InstanceId'] in filtered]
    updates = [i.get('IsLatestVersion') for i in ssmi if i['InstanceId'] in filtered]
    versions = [i.get('PlatformName') for i in ssmi if i['InstanceId'] in filtered]
    titles = ['instance id', 'ip', 'agent up-to-date', 'platform', 'names']
    data = [titles] + list(zip(instances, ips, updates, versions, names))
    return data


args = process_args()
 
session = Session(profile_name=args.profile)
ec2 = session.client('ec2')
ssm = session.client('ssm')

# ssm platform filter
platform = {'Key': 'PlatformTypes', 'Values': (args.platforms or ['Linux', 'Windows'])}

# ec2 tag filter
tags = args.tag.split(':')
tag = {'Name': f"tag:{tags[0]}", 'Values': [tags[1]]}

# list ssm instances
ssmi = ssm_list_instances(platform)

# query ec2 describe instances and apply filter
filtered = [i.get('InstanceId') for x in filtered_instances(tag) for i in x.get('Instances')]

# match filtered ec2 instances with ssm instances
matched = [i.get('InstanceId') for i in ssmi if i.get('InstanceId') in filtered]

if not args.update and not args.iidonly:
    data = build_table(ssmi, filtered)
    for i, d in enumerate(data):
        line = '|'.join(str(x).ljust(22) for x in d)
        print(line)
        if i == 0: print('-' * len(line))
elif args.update:
    ssm_update_agent(matched)
elif args.iidonly:
    print(*matched, sep='\n')
