#!/usr/bin/env python3
"""One synthetic, authenticated recap against the deployed Pinpoint backend; QA user is removed."""
import json,subprocess,urllib.request,urllib.error,secrets,uuid,plistlib
from pathlib import Path
project=Path('supabase/.temp/project-ref').read_text().strip(); assert project=='wcobniubsmvvrggzrkhh'
keys=json.loads(subprocess.check_output(['supabase','projects','api-keys','--project-ref',project,'-o','json'],stderr=subprocess.DEVNULL))
admin=next(k['api_key'] for k in keys if k['name']=='service_role')
config=plistlib.loads(Path('Pinpoint/SupabaseConfig.plist').read_bytes()); public=next(v for v in config.values() if isinstance(v,str) and v.startswith('sb_publishable'))
base='https://'+project+'.supabase.co'
def call(path,body=None,token=None,method='POST',ctype='application/json'):
 headers={'apikey':public,'Content-Type':ctype}
 if token: headers['Authorization']='Bearer '+token
 data=body if isinstance(body,bytes) else json.dumps(body).encode() if body is not None else None
 try:
  with urllib.request.urlopen(urllib.request.Request(base+path,data=data,headers=headers,method=method),timeout=150) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
uid=None
try:
 email='voice-qa-'+uuid.uuid4().hex+'@simulator.invalid';password=secrets.token_urlsafe(32)
 status,user=call('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True},admin);assert status in(200,201),(status,user)
 uid=user['id'];status,session=call('/auth/v1/token?grant_type=password',{'email':email,'password':password});assert status==200
 token=session['access_token']
 transcript="Hole one: I hit the big stick off the outer edge and peeled it into the right rough. Then my seven iron carried 140 yards onto the green. Two putts for a five. Actually, make that four. On hole two I made par with one putt."
 status,result=call('/functions/v1/golf-ai',{'operation':'round_recap','transcript':transcript,'context':{'currentHole':1,'holes':[{'number':1,'par':4},{'number':2,'par':3}]}},token)
 print('Full-round recap:',status,json.dumps(result),flush=True)
 if status==200:
  Path('/tmp/pinpoint-llm-live-response.json').write_text(json.dumps({'transcript':transcript,'response':result}))
  by_hole={h['holeNumber']:h for h in result['holes']}
  assert by_hole[1]['score']==4 and by_hole[1]['putts']==2
  assert by_hole[1]['shots'][0]['club']=='driver' and by_hole[1]['shots'][0]['contact']=='toe'
  assert by_hole[1]['shots'][0]['finish']=='rough' and by_hole[1]['shots'][0]['outcome'] != 'fairway'
  assert by_hole[1]['shots'][1]['carryYards']==140 and by_hole[1]['shots'][1]['distanceYards'] is None
  assert by_hole[2]['score']==3 and by_hole[2]['putts']==1 and by_hole[2]['shots']==[]
  print('PASS real LLM resolves colloquial language, correction and multi-hole summary')
 else:
  assert result.get('code')=='provider_quota_exhausted', 'Unexpected live endpoint error'
  print('BLOCKED: OpenAI quota prevents live accuracy validation')

finally:
 if uid:
  status,_=call('/auth/v1/admin/users/'+uid,token=admin,method='DELETE');assert status in(200,204)
