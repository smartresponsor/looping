// Exact Console MCP capture schema adapter. Empty or ambiguous capture never proves completion.
export function normalizeM5Capture(raw,identity,settle=null) {
  if(raw?.ok!==true || raw?.status!=='MESSAGES_CAPTURED' ||
     raw?.selected?.id?.toUpperCase()!==identity.targetId ||
     raw?.selected?.chat_id?.toLowerCase()!==identity.chatId ||
     raw?.binding?.chatId?.toLowerCase()!==identity.chatId ||
     !Array.isArray(raw.messages) || raw.messages.length<2) {
    return {ok:false,status:'M5_CAPTURE_INSUFFICIENT_EVIDENCE'};
  }
  const textOf=m=>typeof m?.text==='string'?m.text:null;
  const roleOf=m=>m?.role??m?.author?.role??null;
  const last=raw.messages.at(-1),prev=raw.messages.at(-2);
  if(roleOf(prev)!=='user'||roleOf(last)!=='assistant'||!textOf(prev)||!textOf(last)||
     !settle || settle.ok!==true || settle.settled!==true || settle.ready_for_gate!==true ||
     settle.status!=='ANSWER_STABLE' ||
     settle.selected?.id?.toUpperCase()!==identity.targetId ||
     settle.selected?.chat_id?.toLowerCase()!==identity.chatId ||
     settle.binding?.chatId?.toLowerCase()!==identity.chatId ||
     !Array.isArray(settle.messages) ||
     settle.messages.at(-2)?.role!=='user' ||
     settle.messages.at(-2)?.text!==textOf(prev) ||
     settle.messages.at(-1)?.role!=='assistant' ||
     settle.messages.at(-1)?.text!==textOf(last) ||
     settle.latest_assistant?.text!==textOf(last)) return {ok:false,status:'M5_CAPTURE_NOT_SETTLED'};
  return {ok:true,userText:textOf(prev),assistantText:textOf(last),
    responseComplete:true,selected:raw.selected};
}
