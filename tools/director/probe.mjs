// Explicit developer probe; never run by the game or by automated tests.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const config=JSON.parse(fs.readFileSync(path.join(process.env.LOCALAPPDATA,'SurvivorsLedger/director/connection.json')));
const session='probe-'+Date.now();
const snapshot={schema:1,session,request_id:session+'-0-3',revision:0,current_day:3,time:3000,
  state:{role:'escort',stock:{rice:12,wood:1,firewood:0,water:4,nails:0,mugwort:1,flatbread:0},mood:45,
    neighbor:{stage:'aftermath',resolution:'refused',ending:''},relations:{ning:-1,zhou:1,traveler:0},
    history:[{day:2,title:'隔墙求药 · refuse',result:'你留下药品防身，没有答应阿宁。父女另寻医馆。'},{day:3,title:'守宅',result:'米够吃，修门和取暖的柴木却不够。'}],promises:[]}};
const response=await fetch(`http://127.0.0.1:${config.port}/plan`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+config.token},body:JSON.stringify(snapshot),signal:AbortSignal.timeout(150000)});
const result=await response.json();
const filename=path.join(os.tmpdir(),session+'-director.json');
fs.writeFileSync(filename,JSON.stringify({snapshot,status:response.status,result},null,2));
console.log(JSON.stringify({status:response.status,source:result.source,model:result.model,response_id:result.response_id,usage:result.usage,days:result.plan?.days.map(e=>({day:e.day,title:e.title,actor:e.actor})),artifact:filename}));
if(response.status!==200)process.exitCode=1;
