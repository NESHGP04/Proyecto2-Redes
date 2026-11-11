import importlib.util, pathlib, json, tempfile, subprocess, copy, contextlib, io, sys
sys.dont_write_bytecode=True
from unittest.mock import patch
root=pathlib.Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('p4',root/'P4_snmp.py');p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
rows=p.targets()
subnets={r['grupo']:'subnet-'+r['grupo'][7:] for r in rows}
gids={g:'sg-'+g[7:] for g in subnets}
instances=[{'InstanceId':'i-'+str(i),'PrivateIpAddress':r['ip_privada'],'State':{'Name':'running' if r['host'] in ['zp-ldap-01','zp-ti-01','zp-ventas-01'] else 'stopped'},'InstanceType':'t3.small' if r['host']=='zp-monitor-01' else 't3.micro','Architecture':'x86_64','Tags':[{'Key':'Name','Value':r['host']}],'SubnetId':subnets[r['grupo']],'SecurityGroups':[{'GroupName':r['grupo'],'GroupId':gids[r['grupo']]}],'BlockDeviceMappings':[{'Ebs':{'VolumeId':'vol-test'}}]} for i,r in enumerate(rows)]
def acl(g):
    entries=[{'RuleNumber':100,'Egress':eg,'Protocol':'-1','CidrBlock':'0.0.0.0/0','RuleAction':'allow'} for eg in [False,True]]
    return {'NetworkAclId':'acl-'+g,'Entries':entries,'Associations':[{'SubnetId':subnets[g]}]}
base={'describe-vpcs':{'Vpcs':[{'VpcId':'vpc-test','CidrBlock':'10.20.0.0/24'}]},'describe-instances':{'Reservations':[{'Instances':instances}]},'describe-volumes':{'Volumes':[{'VolumeId':'vol-test','Size':16}]},'describe-security-groups':{'SecurityGroups':[{'GroupName':g,'GroupId':gids[g],'IpPermissionsEgress':[{'IpProtocol':'-1','IpRanges':[{'CidrIp':'0.0.0.0/0'}]}],'IpPermissions':[{'IpProtocol':'udp','FromPort':161,'ToPort':161,'UserIdGroupPairs':[{'GroupId':gids['zenite-ti']}]}]} for g in subnets]},'describe-network-interfaces':{'NetworkInterfaces':[{'PrivateIpAddresses':[{'PrivateIpAddress':'10.20.0.103'}]}]},'describe-network-acls':{'NetworkAcls':[acl(g) for g in subnets]},'describe-route-tables':{'RouteTables':[]},'describe-nat-gateways':{'NatGateways':[]},'describe-instance-connect-endpoints':{'InstanceConnectEndpoints':[{'State':'create-complete'}]}}
def case(name,mutate=None,expected=True):
    data=copy.deepcopy(base)
    if mutate:mutate(data)
    calls=[]
    def run(args,**kwargs):
        operation=args[args.index('ec2')+1]
        assert operation.startswith('describe-')
        assert args[args.index('--region')+1]=='us-east-1'
        calls.append(operation)
        return subprocess.CompletedProcess(args,0,json.dumps(data[operation]),'')
    out=io.StringIO()
    with tempfile.TemporaryDirectory() as directory,patch.object(p.Path,'home',return_value=pathlib.Path(directory)),patch.object(p,'run',run),patch.object(p,'tools',lambda *a:None),contextlib.redirect_stdout(out):
        success=True
        try:p.cloud_validate()
        except p.Failure:success=False
        assert success==expected,(name,out.getvalue())
    print('PASS',name)
case('read-only ten-host inventory and restricted SNMP sources')
case('public source rejected',lambda d:d['describe-security-groups']['SecurityGroups'][0]['IpPermissions'][0].update(IpRanges=[{'CidrIp':'0.0.0.0/0'}]),False)
case('TI outside CIDR rejected',lambda d:d['describe-network-interfaces']['NetworkInterfaces'][0]['PrivateIpAddresses'][0].update(PrivateIpAddress='10.20.0.10'),False)
case('missing target rejected',lambda d:d['describe-instances']['Reservations'][0]['Instances'].pop(),False)
case('duplicate target rejected',lambda d:d['describe-instances']['Reservations'][0]['Instances'].append(copy.deepcopy(instances[0])),False)
case('wrong private IP rejected',lambda d:d['describe-instances']['Reservations'][0]['Instances'][0].update(PrivateIpAddress='10.20.0.20'),False)
case('unexpected public IP rejected',lambda d:d['describe-instances']['Reservations'][0]['Instances'][0].update(PublicIpAddress='192.0.2.1'),False)
case('additional SG rejected',lambda d:d['describe-instances']['Reservations'][0]['Instances'][0]['SecurityGroups'].append({'GroupName':'extra','GroupId':'sg-extra'}),False)
case('ACL earlier deny takes precedence',lambda d:d['describe-network-acls']['NetworkAcls'][0]['Entries'].insert(0,{'RuleNumber':50,'Egress':False,'Protocol':'17','CidrBlock':'10.20.0.96/28','RuleAction':'deny','PortRange':{'From':161,'To':161}}),False)
case('missing UDP return rejected',lambda d:d['describe-network-acls']['NetworkAcls'][0]['Entries'][1].update(RuleAction='deny'),False)
case('missing EICE rejected',lambda d:d['describe-instance-connect-endpoints'].update(InstanceConnectEndpoints=[]),False)
case('wrong VPC rejected',lambda d:d['describe-vpcs']['Vpcs'][0].update(CidrBlock='10.21.0.0/24'),False)
case('empty TI interface addresses rejected',lambda d:d['describe-network-interfaces']['NetworkInterfaces'][0].update(PrivateIpAddresses=[]),False)
case('blocked TI SG outbound rejected',lambda d:[g.update(IpPermissionsEgress=[]) for g in d['describe-security-groups']['SecurityGroups'] if g['GroupName']=='zenite-ti'],False)
print('14 AWS-simulation scenarios passed; every attempted API call was describe-*')
