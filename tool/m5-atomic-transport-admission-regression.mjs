import assert from 'node:assert/strict';
import {validateM5AtomicInvocation as verify} from './m5-atomic-transport-admission.mjs';
const id='A'.repeat(32), hash='b'.repeat(64);
const make=(name,args,authorityMode='m5_opt_in')=>({name,authorityMode,arguments:{ports:[9224],expectedTargetId:id,...args}});
const draft=make('write.browser.session.input.draft',{draftText:'isolated test only',allowOverwrite:false,confirmDraft:true});
const submit=make('write.browser.session.submit',{expectedDraftHash:hash,expectedDraftLength:18,confirmSubmit:true});
assert.equal(verify(draft).ok,true);
assert.equal(verify(submit).ok,true);
for(const bad of [
 {...draft,authorityMode:'legacy'},
 make(draft.name,{...draft.arguments,ports:[9223]}),
 make(draft.name,{...draft.arguments,ports:[9222,9224]}),
 make(draft.name,{...draft.arguments,expectedTargetId:'fake'}),
 make(draft.name,{...draft.arguments,draftText:''}),
 make(draft.name,{...draft.arguments,allowOverwrite:true}),
 make(draft.name,{...draft.arguments,confirmDraft:false}),
 make(submit.name,{...submit.arguments,expectedDraftHash:''}),
 make(submit.name,{...submit.arguments,expectedDraftLength:0}),
 make(submit.name,{...submit.arguments,confirmSubmit:false}),
 make('write.browser.session.cmcp.go',{...submit.arguments}),
])assert.equal(verify(bad).ok,false,JSON.stringify(bad));
console.log('M5_ATOMIC_TRANSPORT_ARGUMENT_GATES_PASS');
