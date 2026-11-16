// Shared M5 boundary: a source opt-in is not a valid native GUI target lease.
export function validateM5AtomicInvocation(call) {
  if (!call || call.authorityMode !== 'm5_opt_in') return {ok:false,status:'M5_ATOMIC_AUTHORITY_REQUIRED'};
  const args = call.arguments;
  if (!args || !Array.isArray(args.ports) || args.ports.length !== 1 || args.ports[0] !== 9224
      || typeof args.expectedTargetId !== 'string' || !/^[a-f0-9]{32}$/i.test(args.expectedTargetId)) {
    return {ok:false,status:'M5_ATOMIC_TARGET_PIN_REQUIRED'};
  }
  if (call.name === 'write.browser.session.input.draft') {
    if (typeof args.draftText !== 'string' || !args.draftText.trim() || args.confirmDraft !== true || args.allowOverwrite === true) {
      return {ok:false,status:'M5_ATOMIC_DRAFT_CONTRACT_INVALID'};
    }
  } else if (call.name === 'write.browser.session.submit') {
    if (!/^[a-f0-9]{64}$/.test(args.expectedDraftHash ?? '') ||
        !Number.isInteger(args.expectedDraftLength) || args.expectedDraftLength < 1 || args.confirmSubmit !== true) {
      return {ok:false,status:'M5_ATOMIC_SUBMIT_RECEIPT_REQUIRED'};
    }
  } else {
    return {ok:false,status:'M5_ATOMIC_TOOL_NOT_SUPPORTED'};
  }
  return {ok:true,status:'M5_ATOMIC_ARGUMENTS_VALID'};
}
