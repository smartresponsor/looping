import assert from 'node:assert/strict';
import {normalizeM5Capture as normalize} from './m5-console-capture-adapter.mjs';
const identity={targetId:'F60B5DBF7304A27AD7D4DDC05FDE5E03',chatId:'6afa61bc-fad0-83ea-8cb9-cdba1ac0a043'};
const selected={id:identity.targetId,chat_id:identity.chatId};
const binding={chatId:identity.chatId};
const messages=[{role:'user',text:'ping',hash:'u',index:0},{role:'assistant',text:'pong',hash:'a',index:1}];
const base={ok:true,status:'MESSAGES_CAPTURED',selected,binding,messages};
const settle={ok:true,status:'ANSWER_STABLE',settled:true,ready_for_gate:true,selected,binding,messages,latest_assistant:messages[1]};
assert.equal(normalize(base,identity,settle).ok,true);
assert.equal(normalize(base,identity).ok,false);
for(const bad of [
 {...base,messages:[]},
 {...base,selected:{...selected,id:'F'.repeat(32)}},
 {...base,binding:{chatId:'other'}},
 {...base,messages:[messages[0]]},
 {...base,messages:[messages[1],messages[0]]}
])assert.equal(normalize(bad,identity,settle).ok,false);
for(const bad of [
 {...settle,ok:false}, {...settle,settled:false}, {...settle,ready_for_gate:false},
 {...settle,status:'ANSWER_MAX_WAIT_EXPIRED'},
 {...settle,selected:{...selected,id:'F'.repeat(32)}},
 {...settle,binding:{chatId:'other'}},
 {...settle,messages:[messages[0],{...messages[1],text:'wrong'}]},
 {...settle,latest_assistant:{...messages[1],text:'wrong'}},
 {...settle,messages:[]}
])assert.equal(normalize(base,identity,bad).ok,false);
console.log('M5_CAPTURE_AND_SETTLE_CORRELATION_FAIL_CLOSED_PASS');
