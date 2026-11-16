import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {runScheduledM5,inspectScheduledM5} from './m5-scheduled-coordinator.mjs';
import {buildScheduledM5Identity,plannedM5Actions,applyM5Observation} from './m5-scheduled-state-machine.mjs';
const prompt='M5 isolated smoke';
const identity={occurrenceId:'m5:fixture:001',chatId:'6afa61bc-fad0-83ea-8cb9-cdba1ac0a043',
 targetId:'F60B5DBF7304A27AD7D4DDC05FDE5E03',ports:[9224]};
const hash=createHash('sha256').update(prompt).digest('hex');
const root=await mkdtemp(join(tmpdir(),'m5-coordinator-'));
function adapter({ambiguous=false,wrongTarget=false,noCapture=false}={}) {
 const calls=[];
 const invoke=async(name,args)=>{
  calls.push(name);
  if(name==='read_.browser.chatgpt.composer.preflight')return {ok:true,
   selected:{id:wrongTarget?'F'.repeat(32):identity.targetId,chat_id:identity.chatId},
   auth_state:{authenticated:true},composer:{textLength:0}};
  if(name==='write.browser.session.input.draft')return {ok:true,draft_hash:hash,draft_length:prompt.length};
  if(name==='write.browser.session.submit')return ambiguous?
   {ok:false,status:'SESSION_SUBMIT_NOT_CONFIRMED'}:{ok:true,submitted:true};
  if(name==='read_.browser.chatgpt.message.capture')return noCapture?{ok:true,status:'MESSAGES_CAPTURED',messages:[]}:
   {ok:true,status:'MESSAGES_CAPTURED',selected:{id:identity.targetId,chat_id:identity.chatId},
    binding:{chatId:identity.chatId},messages:[
      {role:'user',text:prompt},{role:'assistant',text:'M5_SMOKE_OK',responseComplete:true}]};
  throw Error('Unexpected tool '+name);
 };
 return {calls,invoke};
}
try{
 const denied=adapter();
 const closed=await runScheduledM5({stateDir:join(root,'closed'),identity,prompt,invoke:denied.invoke});
 assert.equal(closed.status,'M5_SCHEDULED_CUTOVER_OR_LEASE_REQUIRED');
 assert.deepEqual(denied.calls,[]);
 const wrong=adapter({wrongTarget:true});
 const rejected=await runScheduledM5({stateDir:join(root,'wrong'),identity,prompt,invoke:wrong.invoke,cutoverEnabled:true,leaseVerified:true});
 assert.equal(rejected.status,'M5_SCHEDULED_PREFLIGHT_REJECTED');
 assert.equal(wrong.calls.includes('write.browser.session.submit'),false);
 const ok=adapter({ambiguous:true});
 const successful=await runScheduledM5({stateDir:join(root,'ok'),identity,prompt,invoke:ok.invoke,cutoverEnabled:true,leaseVerified:true});
 assert.equal(successful.status,'M5_CAPTURE_READY_FOR_INDEPENDENT_VERIFIER');
 assert.equal(successful.verifiedCompleted,false);
 assert.equal(ok.calls.filter(n=>n==='write.browser.session.submit').length,1);
 const stored=await inspectScheduledM5(successful.path);
 assert.equal(stored.state.stage,'CAPTURED');
 assert.equal(stored.policy.retrySubmitAllowed,false);
 assert.equal(stored.policy.verifiedCompleted,false);
 const replay=await runScheduledM5({stateDir:join(root,'ok'),identity,prompt,invoke:ok.invoke,cutoverEnabled:true,leaseVerified:true});
 assert.equal(replay.status,'M5_SCHEDULED_OCCURRENCE_ALREADY_CLAIMED');
 assert.equal(ok.calls.filter(n=>n==='write.browser.session.submit').length,1);
 const uncertain=adapter({ambiguous:true,noCapture:true});
 const unknown=await runScheduledM5({stateDir:join(root,'unknown'),identity,prompt,invoke:uncertain.invoke,cutoverEnabled:true,leaseVerified:true});
 assert.equal(unknown.status,'M5_RECONCILIATION_REQUIRED');
 assert.equal(unknown.submitRetryAllowed,false);
 assert.deepEqual((await inspectScheduledM5(unknown.path)).policy.allowedTools,['read_.browser.chatgpt.message.capture']);
 const state={schemaVersion:1,identity:buildScheduledM5Identity({...identity,prompt}),
   stage:'SUBMIT_OUTCOME_UNKNOWN',sequence:2,submitAttemptRecorded:true};
 assert.throws(()=>applyM5Observation(state,{type:'submit_dispatched',...identity}),/M5_DUPLICATE_SUBMISSION_FORBIDDEN/);
 for(const bad of [
 {...identity,ports:[9223]}, {...identity,targetId:'invalid'},
 {...identity,chatId:'invalid'}])assert.throws(()=>buildScheduledM5Identity({...bad,prompt}),/M5_SCHEDULED_IDENTITY_REJECTED/);
 assert.equal((await readFile(successful.path,'utf8')).includes('M5_SMOKE_OK'),false);
 console.log('M5_SCHEDULED_COORDINATOR_RECONCILIATION_PASS');
}finally{await rm(root,{recursive:true,force:true});}
