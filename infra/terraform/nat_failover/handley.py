import boto3
import json
import os
import urllib.request

ec2 = boto3.client('ec2', region_name='ap-northeast-2')

RT_A     = os.environ['PRIVATE_RT_A_ID']
RT_C     = os.environ['PRIVATE_RT_C_ID']
ENI_A    = os.environ['NAT_A_ENI_ID']
ENI_C    = os.environ['NAT_C_ENI_ID']
SLACK    = os.environ['SLACK_WEBHOOK_URL']


def handler(event, context):
    message   = json.loads(event['Records'][0]['Sns']['Message'])
    alarm     = message['AlarmName']
    state     = message['NewStateValue']

    if 'nat-ec2-a-status' in alarm:
        if state == 'ALARM':
            before = get_current_eni(RT_A)
            replace_route(RT_A, ENI_C)
            notify("[AZ-A 장애] NAT-A 다운 → Private-RT-A 트래픽을 NAT-C로 전환",
                   before_eni=before, after_eni=ENI_C)
        elif state == 'OK':
            before = get_current_eni(RT_A)
            replace_route(RT_A, ENI_A)
            notify("[AZ-A 복구] NAT-A 정상 → Private-RT-A 트래픽 원복",
                   before_eni=before, after_eni=ENI_A)

    elif 'nat-ec2-c-status' in alarm:
        if state == 'ALARM':
            before = get_current_eni(RT_C)
            replace_route(RT_C, ENI_A)
            notify("[AZ-C 장애] NAT-C 다운 → Private-RT-C 트래픽을 NAT-A로 전환",
                   before_eni=before, after_eni=ENI_A)
        elif state == 'OK':
            before = get_current_eni(RT_C)
            replace_route(RT_C, ENI_C)
            notify("[AZ-C 복구] NAT-C 정상 → Private-RT-C 트래픽 원복",
                   before_eni=before, after_eni=ENI_C)


def get_current_eni(route_table_id):
    rt = ec2.describe_route_tables(RouteTableIds=[route_table_id])
    for route in rt['RouteTables'][0]['Routes']:
        if route.get('DestinationCidrBlock') == '0.0.0.0/0':
            return route.get('NetworkInterfaceId', 'unknown')
    return 'unknown'


def get_instance_id(eni_id):
    if eni_id == 'unknown':
        return 'unknown'
    res = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
    return res['NetworkInterfaces'][0].get('Attachment', {}).get('InstanceId', 'unknown')


def replace_route(route_table_id, eni_id):
    ec2.replace_route(
        RouteTableId=route_table_id,
        DestinationCidrBlock='0.0.0.0/0',
        NetworkInterfaceId=eni_id
    )


def notify(text, before_eni='', after_eni=''):
    before_id = get_instance_id(before_eni)
    after_id  = get_instance_id(after_eni)
    full_text = (
        f"{text}\n"
        f"• 전환 전 ENI: `{before_eni}` (Instance: `{before_id}`)\n"
        f"• 전환 후 ENI: `{after_eni}` (Instance: `{after_id}`)"
    )
    payload = json.dumps({"text": full_text}).encode()
    req = urllib.request.Request(
        SLACK,
        data=payload,
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req)
