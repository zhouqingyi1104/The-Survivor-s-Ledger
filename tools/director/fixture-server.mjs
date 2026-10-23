// Test-only service. No ARK provider is imported or executed here.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createBridge} from './bridge.mjs';
const fixture=JSON.parse(fs.readFileSync(new URL('../../tests/fixtures/director-plan.json',import.meta.url)));
const bridge=createBridge({token:'fixture-only',cooldown:0,provider:async snapshot=>{
  await new Promise(resolve=>setTimeout(resolve,2000));
  const plan=structuredClone(fixture);for(const event of plan.days)event.day+=snapshot.current_day;
  return {source:'ark-plan',fixture:true,plan};
}});
bridge.server.listen(0,'127.0.0.1',()=>{
  fs.writeFileSync(path.join(os.tmpdir(),'ledger-director-fixture.json'),JSON.stringify({port:bridge.server.address().port,token:bridge.token}));
  console.log('Fixture ready');
});
setTimeout(()=>bridge.server.close(),60000).unref();
