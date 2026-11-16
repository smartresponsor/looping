import { createHash } from 'node:crypto';
import { mkdir, open, readFile, rename } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const stages = new Set(['PREPARED','DRAFTED','SUBMIT_OUTCOME_UNKNOWN','SUBMIT_CONFIRMED','CAPTURED','NEEDS_RECONCILIATION']);
const sha = value => createHash('sha256').update(value, 'utf8').digest('hex');
const validId = (value, pattern) => typeof value === 'string' && pattern.test(value);
const targetPattern = /^[a-f0-9]{32}$/i;
const chatPattern = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const occurrencePattern = /^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$/;

export function buildScheduledM5Identity({occurrenceId,chatId,targetId,ports,prompt}) {
  if (!validId(occurrenceId,occurrencePattern) || !validId(chatId,chatPattern) ||
      !validId(targetId,targetPattern) || !Array.isArray(ports) || ports.length !== 1 ||
      ports[0] !== 9224 || typeof prompt !== 'string' || !prompt.trim()) {
    throw Error('M5_SCHEDULED_IDENTITY_REJECTED');
  }
  return Object.freeze({occurrenceId,chatId:chatId.toLowerCase(),targetId:targetId.toUpperCase(),
    ports:[9224],promptSha256:sha(prompt),promptLength:prompt.length});
}
export function plannedM5Actions(state) {
  if (!stages.has(state?.stage)) throw Error('M5_SCHEDULED_STATE_INVALID');
  // Unknown submit must only reconcile; never issue another submit.
  const names={
    PREPARED:['read_.browser.chatgpt.composer.preflight','write.browser.session.input.draft'],
    DRAFTED:['read_.browser.chatgpt.composer.preflight','write.browser.session.submit'],
    SUBMIT_OUTCOME_UNKNOWN:['read_.browser.chatgpt.message.capture'],
    SUBMIT_CONFIRMED:['read_.browser.chatgpt.message.capture'],
    CAPTURED:[],
    NEEDS_RECONCILIATION:['read_.browser.chatgpt.message.capture'],
  };
  return {stage:state.stage,allowedTools:names[state.stage],retrySubmitAllowed:false,
    verifiedCompleted:false};
}
export function applyM5Observation(state,event) {
  if (!stages.has(state?.stage)) throw Error('M5_SCHEDULED_STATE_INVALID');
  if (event?.occurrenceId !== state.identity.occurrenceId ||
      event?.targetId?.toUpperCase() !== state.identity.targetId ||
      event?.chatId?.toLowerCase() !== state.identity.chatId) {
    throw Error('M5_SCHEDULED_IDENTITY_CHANGED');
  }
  let stage;
  switch (event.type) {
    case 'draft_verified':
      if (state.stage !== 'PREPARED' || event.hash !== state.identity.promptSha256 ||
          event.length !== state.identity.promptLength) throw Error('M5_DRAFT_PROOF_REJECTED');
      stage='DRAFTED';break;
    case 'submit_dispatched':
      if (state.stage !== 'DRAFTED') throw Error('M5_DUPLICATE_SUBMISSION_FORBIDDEN');
      // Must persist this state BEFORE invoking the external submit.
      stage='SUBMIT_OUTCOME_UNKNOWN';break;
    case 'submit_confirmed':
      if (state.stage !== 'SUBMIT_OUTCOME_UNKNOWN') throw Error('M5_SUBMIT_TRANSITION_REJECTED');
      stage='SUBMIT_CONFIRMED';break;
    case 'capture_reconciled': {
      if (!['SUBMIT_OUTCOME_UNKNOWN','SUBMIT_CONFIRMED','NEEDS_RECONCILIATION'].includes(state.stage)) throw Error('M5_CAPTURE_TRANSITION_REJECTED');
      const userText=event.userText;
      if (typeof userText !== 'string' || sha(userText) !== state.identity.promptSha256 ||
          userText.length !== state.identity.promptLength ||
          typeof event.assistantText !== 'string' || !event.assistantText.trim() ||
          event.responseComplete !== true) {
        stage='NEEDS_RECONCILIATION';
      } else stage='CAPTURED';
      break;
    }
    case 'reconciliation_inconclusive':
      if (!['SUBMIT_OUTCOME_UNKNOWN','SUBMIT_CONFIRMED','NEEDS_RECONCILIATION'].includes(state.stage)) throw Error('M5_RECONCILIATION_INVALID');
      stage='NEEDS_RECONCILIATION';break;
    default:throw Error('M5_SCHEDULED_EVENT_INVALID');
  }
  return {...state,stage,sequence:state.sequence+1,
    submitAttemptRecorded:state.submitAttemptRecorded || event.type==='submit_dispatched'};
}
export function newM5State(identity) {
  if (!identity?.occurrenceId || !identity?.promptSha256) throw Error('M5_SCHEDULED_IDENTITY_REQUIRED');
  return {schemaVersion:1,identity,stage:'PREPARED',sequence:0,submitAttemptRecorded:false};
}
// Exclusive create by occurrence: a crash cannot turn an uncertain send into a retry.
export async function claimScheduledM5(stateDir,identity) {
  await mkdir(stateDir,{recursive:true,mode:0o700});
  const path=join(stateDir,sha(identity.occurrenceId)+'.json');
  const state=newM5State(identity);
  let handle;
  try {handle=await open(path,'wx',0o600);}
  catch(error){if(error?.code==='EEXIST')return {claimed:false,path};throw error;}
  try {await handle.writeFile(JSON.stringify(state)+'\n');await handle.sync();}
  finally {await handle.close();}
  return {claimed:true,path,state};
}
export async function persistScheduledM5(path,expectedSequence,event) {
  const current=JSON.parse(await readFile(path,'utf8'));
  if(current.sequence!==expectedSequence)throw Error('M5_SCHEDULED_STALE_SEQUENCE');
  const next=applyM5Observation(current,event);
  // Exclusive temporary name and rename are crash-safe writes but this API requires
  // a single external owner lock; do not use as a multi-process compare-and-swap.
  const temp=path+'.'+process.pid+'.tmp';
  const handle=await open(temp,'wx',0o600);
  try {await handle.writeFile(JSON.stringify(next)+'\n');await handle.sync();}
  finally {await handle.close();}
  await rename(temp,path);
  return next;
}
