"""Sin root; puertos solo loopback 13000/12909/19101 y métricas sintéticas.
Requiere tar oficial verificado y binario Prometheus 3.16.0 previamente verificado.
No modifica unidades, servicios, configuración del host ni AWS.
"""
import argparse, tempfile, base64, importlib.util, json, os, pathlib, secrets, shutil, socket, subprocess, tarfile, threading, time, urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest.mock import patch
parser=argparse.ArgumentParser(description='Integración local Grafana/Prometheus con métricas sintéticas; no AWS.')
parser.add_argument('--paquete',type=pathlib.Path,required=True)
parser.add_argument('--prometheus',type=pathlib.Path,required=True)
args=parser.parse_args()
ROOT=pathlib.Path(tempfile.mkdtemp(prefix='p4-grafana-integration-'))
BASE=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('grafana_local',BASE/'P4_grafana.py'); g=importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
g.p4=g.core()
for port in (13000,12909,19101,19102):
 s=socket.socket(); s.bind(('127.0.0.1',port)); s.close()
archive=args.paquete.resolve()
g.verified(archive)
if not (ROOT/'grafana-13.3.0').exists():
 with tarfile.open(archive) as t: g.extract(t,ROOT)
g.CONF=ROOT/'conf'; g.DATA=ROOT/'data'; g.LIB=ROOT/'grafana-13.3.0'
shutil.rmtree(g.DATA, ignore_errors=True); shutil.rmtree(ROOT/'prom-data', ignore_errors=True)
g.CONF.mkdir(exist_ok=True); g.DATA.mkdir(exist_ok=True)
for p in ['provisioning/datasources','provisioning/dashboards','dashboard']:(g.CONF/p).mkdir(parents=True,exist_ok=True)
password=secrets.token_urlsafe(32)
(g.CONF/'admin-password').write_text(password); (g.CONF/'secret-key').write_text(secrets.token_urlsafe(48))
for p in ['admin-password','secret-key']: (g.CONF/p).chmod(0o600)
(g.CONF/'grafana.ini').write_text(g.configuration().replace('http_port = 3000','http_port = 13000').replace('localhost:3000','localhost:13000'))
(g.CONF/'dashboard/zenite.json').write_text(json.dumps(g.dashboard()))
(g.CONF/'provisioning/datasources/zenite.yml').write_text(json.dumps({'apiVersion':1,'datasources':[{'uid':g.DS_UID,'name':'Zenite Prometheus','type':'prometheus','access':'proxy','url':'http://127.0.0.1:12909','isDefault':True}]}))
(g.CONF/'provisioning/dashboards/zenite.yml').write_text(json.dumps({'apiVersion':1,'providers':[{'name':'zenite','type':'file','folder':'Zenite','disableDeletion':True,'allowUiUpdates':False,'options':{'path':str(g.CONF/'dashboard')}}]}))
class Metrics(BaseHTTPRequestHandler):
 def do_GET(self):
  n=int(time.monotonic()*1000)
  body=('hrProcessorLoad{hrDeviceIndex="1"} 17\nhrStorageUsed{hrStorageDescr="Physical memory",hrStorageIndex="1"} 128\nhrStorageSize{hrStorageDescr="Physical memory",hrStorageIndex="1"} 512\nifHCInOctets{ifName="eth0",ifIndex="2"} '+str(n)+'\nifHCOutOctets{ifName="eth0",ifIndex="2"} '+str(n*2)+'\ndskPercent{dskPath="/",dskIndex="1"} 35\nsysUpTime 23400\nprCount{prNames="sshd",prIndex="1"} 1\n').encode()
  self.send_response(200); self.send_header("Content-Type","text/plain; version=0.0.4"); self.end_headers(); self.wfile.write(body)
 def log_message(self,*a):pass
server=HTTPServer(('127.0.0.1',19101),Metrics); threading.Thread(target=server.serve_forever,daemon=True).start()
config={'global':{'scrape_interval':'2s'},'scrape_configs':[{'job_name':'snmp','static_configs':[{'targets':['127.0.0.1:'+('19102' if name=='zp-vpn-01' else '19101')],'labels':{'host':name,'instance':ip}} for name,ip in g.p4.IPS.items()]},{'job_name':'snmp_exporter','static_configs':[{'targets':['127.0.0.1:19101']}]}]}
(ROOT/'prom.json').write_text(json.dumps(config))
procs=[]
def api(path,auth=False,body=None):
 headers={}
 if auth:headers['Authorization']='Basic '+base64.b64encode((g.ADMIN+':'+password).encode()).decode()
 if body is not None:headers['Content-Type']='application/json'
 req=urllib.request.Request('http://127.0.0.1:13000'+path,headers=headers,data=json.dumps(body).encode() if body is not None else None)
 with urllib.request.urlopen(req,timeout=30) as r:return json.load(r)
try:
 for argv,log in [([str(args.prometheus.resolve()),'--config.file='+str(ROOT/'prom.json'),'--storage.tsdb.path='+str(ROOT/'prom-data'),'--web.listen-address=127.0.0.1:12909'],'prom.log'),([str(g.LIB/'bin/grafana'),'server','--homepath='+str(g.LIB),'--config='+str(g.CONF/'grafana.ini')],'grafana.log')]:
  f=(ROOT/log).open('w'); procs.append(subprocess.Popen(argv,stdout=f,stderr=subprocess.STDOUT)); f.close()
 for n in range(90):
  try:
   health=api('/api/health')
   if health.get('database')=='ok':break
  except Exception:pass
  assert all(p.poll() is None for p in procs),'Proceso terminó; revisar logs privados locales'
  time.sleep(1)
 else:raise RuntimeError('Grafana local no inició en 90s')
 assert health['version']==g.VERSION
 print('PASS Grafana OSS '+g.VERSION+' real: inicio sin root, SQLite y configuración file-provider')
 try:api('/api/user')
 except urllib.error.HTTPError as e:assert e.code==401
 else:raise AssertionError('Acceso anónimo permitido')
 doc=api('/api/dashboards/uid/'+g.DASH_UID,True)['dashboard']
 assert len(doc['panels'])==10
 print('PASS autenticación exigida, contraseña sintética y diez paneles provisionados')
 time.sleep(6)
 with urllib.request.urlopen('http://127.0.0.1:12909/api/v1/query?query=up%7Bjob%3D%22snmp%22%7D') as response: targets=json.load(response)['data']['result']
 assert sum(t['value'][1]=='1' for t in targets)==9 and sum(t['value'][1]=='0' for t in targets)==1, 'Fixture no tiene 9 up / 1 down'
 for panel in g.dashboard()['panels']:
  expr=panel['targets'][0]['expr'].replace('$host','.*')
  body={'from':str(int(time.time()-120)*1000),'to':str(int(time.time())*1000),'queries':[{'refId':'A','datasource':{'uid':g.DS_UID,'type':'prometheus'},'expr':expr,'instant':True,'range':False,'intervalMs':2000,'maxDataPoints':100}]}
  data=api('/api/ds/query',True,body)
  frames=data['results']['A'].get('frames',[])
  assert not data['results']['A'].get('error'), panel['title']
  assert frames and any(f.get('data',{}).get('values') for f in frames),panel['title']+' sin datos'
  print('PASS consulta Grafana -> Prometheus: '+panel['title'])
 print('PASS estado sin respuesta visible como dato; un objetivo sintético down, nueve up')
 print('LOCAL: métricas sintéticas; no AWS, no systemd ni permisos reales del usuario de servicio en EC2.')
finally:
 for p in procs:
  p.terminate()
 for p in procs:
  try:p.wait(timeout=10)
  except subprocess.TimeoutExpired:p.kill();p.wait()
 server.shutdown()
 shutil.rmtree(ROOT)
