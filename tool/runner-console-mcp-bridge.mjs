import { Client } from "../../console-mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js";
import { StreamableHTTPClientTransport } from "../../console-mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js";
import fs from "node:fs/promises";

const allowedTools = new Set([
  "console.write.browser.session.cmcp.go",
  "console.read_.repo.context.capture",
  "console.read_.repo.workspace.status",
  "console.read_.repo.memory.graph.plan",
  "console.write.engine.task.enqueue",
  "console.write.engine.worker.tick",
  "console.write.engine.chat.bind",
  "console.write.engine.answer.capture",
  "console.write.engine.gateway.decide",
  "console.write.engine.reply.draft",
  "console.write.engine.reply.submit",
]);

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) continue;
    const name = key.slice(2);
    const value = argv[i + 1];
    if (typeof value === "undefined" || value.startsWith("--")) {
      args[name] = true;
    } else {
      args[name] = value;
      i += 1;
    }
  }
  return args;
}

function parseToolPayload(result) {
  const text = result?.content?.[0]?.text ?? "";
  try {
    return JSON.parse(text);
  } catch {
    return { ok: false, status: "CONSOLE_MCP_BRIDGE_NON_JSON_RESULT", raw: text };
  }
}

async function readToolCall(payloadPath) {
  const payload = JSON.parse(await fs.readFile(payloadPath, "utf8"));
  const plan = payload.runnerExecutionPlan;
  if (!plan || typeof plan.tool !== "string") {
    throw new Error("runnerExecutionPlan.tool missing");
  }
  return { name: plan.tool, arguments: plan.arguments ?? {} };
}

async function main() {
  const args = parseArgs(process.argv);
  const payloadPath = args.payload;
  const resultPath = args.result;
  if (!payloadPath) throw new Error("--payload is required");
  if (!resultPath) throw new Error("--result is required");

  const toolCall = await readToolCall(payloadPath);
  if (!allowedTools.has(toolCall.name)) {
    throw new Error(`console-mcp bridge tool not allowed: ${toolCall.name}`);
  }

  const token = process.env.CONSOLE_MCP_BEARER_TOKEN ?? "";
  if (!token) throw new Error("CONSOLE_MCP_BEARER_TOKEN is required");
  const endpoint = new URL(process.env.CONSOLE_MCP_ENDPOINT ?? "http://127.0.0.1:3334/mcp");
  const transport = new StreamableHTTPClientTransport(endpoint, {
    requestInit: { headers: { Authorization: `Bearer ${token}` } },
  });
  const client = new Client({ name: "chatgpt-loop-runner-bridge", version: "1.0.0" });

  try {
    await client.connect(transport);
    const result = await client.callTool({ name: toolCall.name, arguments: toolCall.arguments ?? {} });
    const parsed = parseToolPayload(result);
    const ok = parsed.ok !== false;
    const wrapped = {
      ...parsed,
      ok,
      tool: toolCall.name,
      status: typeof parsed.status === "string" ? parsed.status : (ok ? "CONSOLE_MCP_TOOL_COMPLETED" : "CONSOLE_MCP_TOOL_FAILED"),
      bridge: {
        ok,
        status: "CONSOLE_MCP_BRIDGE_TOOL_EXECUTED",
        endpoint: endpoint.toString(),
      },
    };
    await fs.writeFile(resultPath, `${JSON.stringify(wrapped, null, 2)}\n`, "utf8");
    process.stdout.write(`${JSON.stringify({
      ok: wrapped.ok,
      status: "CONSOLE_MCP_BRIDGE_EXECUTED",
      tool: toolCall.name,
      resultPath,
      resultStatus: wrapped.status,
      submitted: wrapped.submitted?.submitted === true || wrapped.submitted === true,
      chatId: wrapped.chatId ?? wrapped.chat_id ?? wrapped.cmcp_go_trace?.opened_chat_id ?? null,
      targetId: wrapped.targetId ?? wrapped.target_id ?? wrapped.cmcp_go_trace?.opened_target_id ?? null,
    }, null, 2)}\n`);
  } finally {
    await transport.close().catch(() => undefined);
    await client.close?.();
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
