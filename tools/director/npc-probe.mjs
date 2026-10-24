// Explicit authorized developer probe. Reusing this request ID recovers its paid result.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createBridge,arkProvider,validateSnapshot} from './bridge.mjs';

const [snapshotFile,directory,binary]=process.argv.slice(2);
if(!snapshotFile||!directory||!binary)throw Error('Expected isolated temporary snapshot, temporary output directory and explicit ARK binary');
const inTemporary=value=>{const relative=path.relative(os.tmpdir(),path.resolve(value));return relative!==''&&!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative);};
if(!inTemporary(snapshotFile)||!inTemporary(directory))throw Error('Probe requires isolated temporary fixture paths');
const snapshot=JSON.parse(fs.readFileSync(snapshotFile,'utf8'));
if(!validateSnapshot(snapshot)||snapshot.state.npc_dialogue?.slots?.length!==3)throw Error('Export a valid Godot fixture with three unread pending NPC decisions');
fs.mkdirSync(directory,{recursive:true});
const bridge=createBridge({provider:arkProvider(binary,'agent-plan_cn-beijing_personal',path.join(directory,'audit')),cacheFile:path.join(directory,'requests.json')});
await new Promise(resolve=>bridge.server.listen(0,'127.0.0.1',resolve));
try{
  const response=await fetch(`http://127.0.0.1:${bridge.server.address().port}/plan`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+bridge.token},body:JSON.stringify(snapshot),signal:AbortSignal.timeout(170000)});
  const result=await response.json(),artifact=path.join(directory,'result.json');
  fs.writeFileSync(artifact,JSON.stringify({snapshot,status:response.status,result},null,2));
  console.log(JSON.stringify({status:response.status,error:result.error,source:result.source,model:result.model,response_id:result.response_id,usage:result.usage,npc_dialogue:result.plan?.npc_dialogue,artifact}));
  if(response.status!==200||result.plan?.npc_dialogue?.length!==3)process.exitCode=1;
}finally{await new Promise(resolve=>bridge.server.close(resolve));}
