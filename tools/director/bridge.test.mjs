import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createBridge,validatePlan,validateSnapshot,buildPrompt} from './bridge.mjs';
const plan=JSON.parse(fs.readFileSync(new URL('../../tests/fixtures/director-plan.json',import.meta.url)));
const snapshot={schema:1,request_id:'fixture-0-0',session:'fixture',revision:0,current_day:0,time:0,state:{role:'escort',stock:{wood:1,rice:5},mood:60,neighbor:{stage:'waiting',resolution:'',ending:''},relations:{ning:0,zhou:0,traveler:0},history:[],promises:[]}};
async function start(options){const b=createBridge(options);await new Promise(r=>b.server.listen(0,'127.0.0.1',r));return {...b,url:`http://127.0.0.1:${b.server.address().port}`};}
const request=(b,body=snapshot,headers={})=>fetch(b.url+'/plan',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+b.token,...headers},body:JSON.stringify(body)});
const close=b=>new Promise(r=>b.server.close(r));
test('typed plans reject arbitrary effects, oversized rewards, unaffordable-only choices, duplicate days and hollow choices',()=>{
  assert(validatePlan(plan,0));assert(validateSnapshot(snapshot));
  for(const mutate of [p=>p.days[0].choices[0].give={gold:99},p=>p.days[0].choices[0].give={rice:4},p=>p.days[0].script='execute',p=>p.days[1].day=1,p=>p.days[0].choices[1].req={water:1},p=>p.days[2].choices[1].mood=0,p=>p.days[0].choices[0].req=null,p=>p.days[0].choices[0].mood=null,p=>p.days[0].choices[0].after=null]){const p=structuredClone(plan);mutate(p);assert.equal(validatePlan(p,0),false);}
  assert.equal(validateSnapshot({...snapshot,api_key:'not-allowed'}),false);
  assert.equal(validateSnapshot({...snapshot,request_id:'wrong'}),false);
  const s=structuredClone(snapshot);s.state.history=[{day:1,title:'拒绝借粮',result:'留下米给自己'}];assert(buildPrompt(s).includes('拒绝借粮'));
});
test('slow provider is asynchronous; duplicate and conflicting requests cannot generate twice',async()=>{
  let calls=0,release;const pending=new Promise(r=>release=r);
  const b=await start({cooldown:0,provider:async()=>{calls++;await pending;return {source:'ark-plan',plan};}});
  try{
    const first=request(b);await new Promise(r=>setTimeout(r,25));
    const health=await fetch(b.url+'/health',{headers:{Authorization:'Bearer '+b.token}});assert.equal(health.status,200);
    assert.equal((await request(b)).status,409);release();assert.equal((await first).status,200);
    assert.equal((await request(b)).status,200);assert.equal(calls,1);
    const changed=structuredClone(snapshot);changed.state.stock.rice=2;assert.equal((await request(b,changed)).status,409);
  }finally{release();await close(b);}
});
test('auth, browser-origin, schema and per-day call budget fail closed without provider calls',async()=>{
  let calls=0;const b=await start({cooldown:0,maxCalls:1,provider:async()=>{calls++;return {source:'ark-plan',plan};}});
  try{
    assert.equal((await request(b,snapshot,{Authorization:'wrong'})).status,401);
    assert.equal((await request(b,snapshot,{Origin:'http://example.test'})).status,403);
    assert.equal((await request(b,{...snapshot,schema:2})).status,400);assert.equal(calls,0);
    assert.equal((await request(b)).status,200);
    assert.equal((await request(b,{...snapshot,session:'other',request_id:'other-0-0'})).status,429);assert.equal(calls,1);
  }finally{await close(b);}
});
test('lost/failed requests remain attempted across bridge restart, never silently retried',async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ledger-director-test-'));const cacheFile=path.join(dir,'requests.json');let calls=0;
  let b=await start({cacheFile,cooldown:0,provider:async()=>{calls++;throw Error('fixture provider failed');}});
  try{assert.equal((await request(b)).status,503);await close(b);b=await start({cacheFile,cooldown:0,provider:async()=>{calls++;return {source:'ark-plan',plan};}});assert.equal((await request(b)).status,409);assert.equal(calls,1);}finally{await close(b);fs.unlinkSync(cacheFile);fs.rmdirSync(dir);}
});
