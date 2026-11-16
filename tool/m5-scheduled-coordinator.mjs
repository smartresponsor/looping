import {readFile} from 'node:fs/promises';
import {validateM5AtomicInvocation} from './m5-atomic-transport-admission.mjs';
import {
 buildScheduledM5Identity,claimScheduledM5,persistScheduledM5,plannedM5Actions
} from './m5-scheduled-state-machine.mjs';

// Explicit adapter injection: production bridge must separately prove a native GUI lease.
// No global process-level opt-in and no automatic retry on ambiguous submission.
export async function runScheduledM5({
  stateDir,identity:input,prompt,invoke,cutoverEnabled=false,leaseVerified=false
}) {
  if(cutoverEnabled!==true || leaseVerified!==true) {
    return {ok:false,status:'M5_SCHEDULED_CUTOVER_OR_LEASE_REQUIRED',dispatched:false};
  }
  if(typeof invoke!=='function')throw Error('M5_SCHEDULED_INVOKER_REQUIRED');
  const identity=buildScheduledM5Identity({...input,prompt});
  const claim=await claimScheduledM5(stateDir,identity);
  if(!claim.claimed)return {ok:false,status:'M5_SCHEDULED_OCCURRENCE_ALREADY_CLAIMED',dispatched:false};
  const base={ports:[9224],expectedTargetId:identity.targetId};
  const event=(type,other={})=>({type,occurrenceId:identity.occurrenceId,
    targetId:identity.targetId,chatId:identity.chatId,...other});
  let state=claim.state;
  const update=async e=>{state=await persistScheduledM5(claim.path,state.sequence,e);};
  const preflight=await invoke('read_.browser.chatgpt.composer.preflight',base);
  if(preflight?.ok!==true || preflight?.selected?.id?.toUpperCase()!==identity.targetId ||
    preflight?.selected?.chat_id?.toLowerCase()!==identity.chatId ||
    preflight?.auth_state?.authenticated!==true ||
    preflight?.composer?.textLength!==0) {
    return {ok:false,status:'M5_SCHEDULED_PREFLIGHT_REJECTED',dispatched:false,path:claim.path};
  }
  const draftArgs={...base,draftText:prompt,allowOverwrite:false,confirmDraft:true};
  const draftGate=validateM5AtomicInvocation({name:'write.browser.session.input.draft',authorityMode:'m5_opt_in',arguments:draftArgs});
  if(!draftGate.ok)throw Error(draftGate.status);
  const draft=await invoke('write.browser.session.input.draft',draftArgs);
  if(draft?.ok!==true || draft?.draft_hash!==identity.promptSha256 ||
    draft?.draft_length!==identity.promptLength) {
    return {ok:false,status:'M5_SCHEDULED_DRAFT_UNCONFIRMED',dispatched:false,path:claim.path};
  }
  await update(event('draft_verified',{hash:draft.draft_hash,length:draft.draft_length}));
  // Durable write ahead of submit. A killed process leaves one immutable attempt.
  await update(event('submit_dispatched'));
  let response;
  try {
    const submitArgs={...base,expectedDraftHash:draft.draft_hash,expectedDraftLength:draft.draft_length,
        confirmSubmit:true};
    const submitGate=validateM5AtomicInvocation({name:'write.browser.session.submit',authorityMode:'m5_opt_in',arguments:submitArgs});
    if(!submitGate.ok)throw Error(submitGate.status);
    response=await invoke('write.browser.session.submit',submitArgs);
  } catch {
    response={ok:false,status:'SUBMIT_OUTCOME_UNKNOWN'};
  }
  if(response?.ok===true && response?.submitted===true)await update(event('submit_confirmed'));
  // Reconciliation is read-only. If it fails, no second submit.
  let capture;
  try {
    capture=await invoke('read_.browser.chatgpt.message.capture',
      {...base,preferredChatId:identity.chatId,requireChatId:true,maxMessages:10});
  } catch {capture=null;}
  if(capture?.ok===true && capture?.selected?.id?.toUpperCase()===identity.targetId &&
    capture?.selected?.chat_id?.toLowerCase()===identity.chatId &&
    typeof capture.userText==='string' && typeof capture.assistantText==='string') {
    await update(event('capture_reconciled',{userText:capture.userText,
      assistantText:capture.assistantText,responseComplete:capture.responseComplete}));
  } else await update(event('reconciliation_inconclusive'));
  return {ok:state.stage==='CAPTURED',
    status:state.stage==='CAPTURED'?'M5_CAPTURE_READY_FOR_INDEPENDENT_VERIFIER':'M5_RECONCILIATION_REQUIRED',
    stage:state.stage,dispatched:true,verifiedCompleted:false,submitRetryAllowed:false,path:claim.path};
}
export async function inspectScheduledM5(path) {
 const state=JSON.parse(await readFile(path,'utf8'));
 return {state,policy:plannedM5Actions(state)};
}
