import assert from 'node:assert/strict';
import {normalizeM5Capture} from './m5-console-capture-adapter.mjs';
const identity={targetId:'F60B5DBF7304A27AD7D4DDC05FDE5E03',chatId:'6afa61bc-fad0-83ea-8cb9-cdba1ac0a043'};
const empty={ok:true,status:'MESSAGES_CAPTURED',selected:{id:identity.targetId,chat_id:identity.chatId},
 binding:{chatId:identity.chatId},messages:[]};
const settle={ok:false,status:'ANSWER_MAX_WAIT_EXPIRED',settled:false,ready_for_gate:false,
 selected:{id:identity.targetId,chat_id:identity.chatId},messages:[]};
const dom={ok:true,targetId:identity.targetId,visibleText:'You said: VIKUNJING M5 BROWSER ADMISSION SMOKE TEST. ChatGPT said: VIKUNJING_M5_CHAT_BOUND_OK Response complete'};
assert.equal(normalizeM5Capture(empty,identity).ok,false);
assert.equal(normalizeM5Capture(settle,identity).ok,false);
assert.equal(normalizeM5Capture(dom,identity).ok,false);
console.log('M5_REAL_READONLY_EVIDENCE_FAIL_CLOSED_PASS');
