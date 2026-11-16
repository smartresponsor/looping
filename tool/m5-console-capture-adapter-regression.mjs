import assert from 'node:assert/strict';
import {normalizeM5Capture as normalize} from './m5-console-capture-adapter.mjs';
const identity={targetId:'F60B5DBF7304A27AD7D4DDC05FDE5E03',chatId:'6afa61bc-fad0-83ea-8cb9-cdba1ac0a043'};
const base={ok:true,status:'MESSAGES_CAPTURED',selected:{id:identity.targetId,chat_id:identity.chatId},
 binding:{chatId:identity.chatId},messages:[{role:'user',text:'ping'},
 {role:'assistant',text:'pong',responseComplete:true}]};
assert.equal(normalize(base,identity).ok,true);
for(const bad of [
 {...base,messages:[]},
 {...base,selected:{...base.selected,id:'F'.repeat(32)}},
 {...base,binding:{chatId:'other'}},
 {...base,messages:[{role:'user',text:'ping'}]},
 {...base,messages:[{role:'user',text:'ping'},{role:'assistant',text:'pong'}]},
 {...base,messages:[{role:'assistant',text:'pong',responseComplete:true},{role:'user',text:'ping'}]},
])assert.equal(normalize(bad,identity).ok,false);
console.log('M5_CONSOLE_CAPTURE_SCHEMA_FAIL_CLOSED_PASS');
