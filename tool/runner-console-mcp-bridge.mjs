import { Client } from "../../console-mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js";
import { StreamableHTTPClientTransport } from "../../console-mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js";
import fs from "node:fs/promises";

const atomicTools = new Set([
  "console.write.browser.session.title.prefix",
  "console.write.browser.chatgpt.chat.delete.execute",
  "console.read_.browser.chatgpt.composer.preflight",
  "console.read_.browser.chatgpt.watch.probe",
  "console.read_.browser.chatgpt.answer.settle",
  "console.read_.browser.chatgpt.message.capture",
  "console.read_.repo.context.capture",
  "console.read_.repo.file.bundle.read",
  "console.read_.repo.workspace.status",
  "console.read_.runtime.php.server.status",
  "console.read_.runtime.mobile.edge.server.status",
  "console.read_.runtime.visual.gallery.server.status",
  "console.read_.repo.git.branch.status",
  "console.read_.repo.implementation.run.capture",
  "console.read_.repo.gate.check.run",
  "console.read_.repo.memory.graph.plan",
]);

const m5AtomicWriteTools = new Set([
  "console.write.browser.session.open",
  "console.write.browser.session.input.draft",
  "console.write.browser.session.submit",
]);

const durableAsyncTools = new Set([
  "console.write.engine.cycle.rounds.start",
  "console.read_.engine.cycle.rounds.status",
  "console.read_.engine.cycle.rounds.output",
  "console.write.engine.cycle.rounds.stop",
]);

const legacyOrchestrationTools = new Set([
  "console.write.browser.session.cmcp.go",
  "console.write.browser.chatgpt.chat.adopt_go",
  "console.read_.browser.chatgpt.watch.next",
  "console.read_.browser.chatgpt.run.loop.plan",
  "console.read_.browser.chatgpt.run.loop.step",
  "console.read_.browser.chatgpt.run.loop.step.summary",
  "console.read_.browser.chatgpt.run.loop.auto.summary",
  "console.write.browser.session.run.loop.daemon.start",
  "console.write.engine.cycle.step",
  "console.write.engine.cycle.run",
  "console.write.engine.task.enqueue",
  "console.write.engine.worker.tick",
  "console.write.engine.chat.bind",
  "console.write.engine.answer.capture",
  "console.write.engine.gateway.decide",
  "console.write.engine.reply.draft",
  "console.write.engine.reply.submit",
]);

const allowedTools = new Set([...atomicTools, ...durableAsyncTools, ...legacyOrchestrationTools]);

function m5AtomicTransportEnabled() {
  return process.env.CHATGPT_LOOP_M5_ATOMIC_TRANSPORT_ENABLED === "1";
}

function toolAllowed(toolCall) {
  if (allowedTools.has(toolCall.name)) return true;
  return m5AtomicWriteTools.has(toolCall.name)
    && toolCall.authorityMode === "m5_opt_in"
    && m5AtomicTransportEnabled();
}

function capabilityClass(toolCall) {
  if (atomicTools.has(toolCall.name)) return "atomic";
  if (m5AtomicWriteTools.has(toolCall.name)) return "atomic_m5_gated";
  if (durableAsyncTools.has(toolCall.name)) return "durable_async";
  return legacyOrchestrationTools.has(toolCall.name) ? "legacy_orchestration" : "unknown";
}

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
  const structured = result?.structuredContent;
  if (structured && typeof structured === "object" && !Array.isArray(structured)) {
    return structured;
  }

  const textItems = Array.isArray(result?.content)
    ? result.content.filter((item) => item?.type === "text" && typeof item.text === "string")
    : [];
  const text = textItems.map((item) => item.text).join("\n").trim();
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
  return {
    name: plan.tool,
    arguments: plan.arguments ?? {},
    authorityMode: typeof plan.authorityMode === "string" ? plan.authorityMode : "legacy",
  };
}

function readPositiveIntEnv(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? "", 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function resolveToolRequestTimeoutMs(toolName) {
  const defaultTimeoutMs = readPositiveIntEnv("CONSOLE_MCP_BRIDGE_TOOL_TIMEOUT_MS", 120000);
  const engineTimeoutMs = readPositiveIntEnv("CONSOLE_MCP_BRIDGE_ENGINE_TIMEOUT_MS", 1800000);
  const longToolPrefixes = [
    "console.write.browser.session.cmcp.go",
    "console.write.browser.chatgpt.chat.adopt_go",
    "console.write.engine.answer.capture",
  ];
  return longToolPrefixes.some((prefix) => toolName === prefix || toolName.startsWith(`${prefix}.`)) ? engineTimeoutMs : defaultTimeoutMs;
}

async function main() {
  const args = parseArgs(process.argv);
  const payloadPath = args.payload;
  const resultPath = args.result;
  if (!payloadPath) throw new Error("--payload is required");
  if (!resultPath) throw new Error("--result is required");

  const toolCall = await readToolCall(payloadPath);
  if (!toolAllowed(toolCall)) {
    throw new Error(`console-mcp bridge tool not allowed: ${toolCall.name}`);
  }

  const token = process.env.CONSOLE_MCP_BEARER_TOKEN ?? "";
  if (!token) throw new Error("CONSOLE_MCP_BEARER_TOKEN is required");
  const endpoint = new URL(process.env.CONSOLE_MCP_ENDPOINT ?? "http://127.0.0.1:3335/mcp");
  const transport = new StreamableHTTPClientTransport(endpoint, {
    requestInit: { headers: { Authorization: `Bearer ${token}` } },
  });
  const client = new Client({ name: "chatgpt-loop-runner-bridge", version: "1.0.0" });

  try {
    await client.connect(transport);
    const requestTimeoutMs = resolveToolRequestTimeoutMs(toolCall.name);
    const requestOptions = { timeout: requestTimeoutMs, maxTotalTimeout: requestTimeoutMs };
    const result = await client.callTool(
      { name: toolCall.name, arguments: toolCall.arguments ?? {} },
      undefined,
      requestOptions
    );
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
        capabilityClass: capabilityClass(toolCall),
        authorityMode: toolCall.authorityMode,
        m5AtomicTransportEnabled: m5AtomicTransportEnabled(),
        endpoint: endpoint.toString(),
        requestTimeoutMs,
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
      requestTimeoutMs,
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
