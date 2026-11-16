// Exact Console MCP capture schema adapter. Empty or ambiguous capture never proves completion.
export function normalizeM5Capture(raw,identity) {
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
     last?.responseComplete!==true) return {ok:false,status:'M5_CAPTURE_NOT_SETTLED'};
  return {ok:true,userText:textOf(prev),assistantText:textOf(last),
    responseComplete:true,selected:raw.selected};
}
