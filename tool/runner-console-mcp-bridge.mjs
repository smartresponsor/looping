import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Resolve only the configured Console MCP installation or the conventional
// sibling installation, including checkouts under the dedicated .worktrees root.
function resolveConsoleMcpRoot() {
  const configured = process.env.LOOPING_CONSOLE_MCP_ROOT;
  if (configured !== undefined) {
    if (!configured.trim() || !path.isAbsolute(configured)) {
      throw new Error("LOOPING_CONSOLE_MCP_ROOT_INVALID");
    }
    return path.normalize(configured);
  }
  const projectRoot = fileURLToPath(new URL("../", import.meta.url));
  const parent = path.dirname(path.resolve(projectRoot));
  const workspace = path.basename(parent) === ".worktrees" ? path.dirname(parent) : parent;
  return path.join(workspace, "console-mcp");
}

async function loadConsoleMcpSdk() {
  const sdkRoot = path.join(resolveConsoleMcpRoot(), "node_modules", "@modelcontextprotocol", "sdk");
  try {
    const metadata = JSON.parse(await fs.readFile(path.join(sdkRoot, "package.json"), "utf8"));
    if (metadata.name !== "@modelcontextprotocol/sdk" || typeof metadata.version !== "string") {
      throw new Error("SDK metadata invalid");
    }
    const { Client } = await import(pathToFileURL(path.join(sdkRoot, "dist", "esm", "client", "index.js")).href);
    const { StreamableHTTPClientTransport, StreamableHTTPError } = await import(pathToFileURL(path.join(sdkRoot, "dist", "esm", "client", "streamableHttp.js")).href);
    const { UnauthorizedError } = await import(pathToFileURL(path.join(sdkRoot, "dist", "esm", "client", "auth.js")).href);
    if ([Client, StreamableHTTPClientTransport, StreamableHTTPError, UnauthorizedError].some(value => typeof value !== "function")) {
      throw new Error("SDK exports invalid");
    }
    return { Client, StreamableHTTPClientTransport, StreamableHTTPError, UnauthorizedError, version: metadata.version };
  } catch {
    throw new Error("LOOPING_CONSOLE_MCP_SDK_UNAVAILABLE");
  }
}
import { validateM5AtomicInvocation } from "./m5-atomic-transport-admission.mjs";

const atomicTools = new Set([
  "write.browser.session.title.prefix",
  "write.browser.chatgpt.chat.delete.execute",
  "read_.browser.chatgpt.composer.preflight",
  "read_.browser.chatgpt.watch.probe",
  "read_.browser.chatgpt.answer.settle",
  "read_.browser.chatgpt.message.capture",
  "read_.repo.context.capture",
  "read_.repo.file.bundle.read",
  "read_.repo.workspace.status",
  "read_.runtime.php.server.status",
  "read_.runtime.mobile.edge.server.status",
  "read_.runtime.visual.gallery.server.status",
  "read_.repo.git.branch.status",
  "read_.repo.implementation.run.capture",
  "read_.repo.gate.check.run",
  "read_.repo.memory.graph.plan",
]);

const m5AtomicWriteTools = new Set([
  "write.browser.session.open",
  "write.browser.session.input.draft",
  "write.browser.session.submit",
]);

const durableAsyncTools = new Set([
  "write.engine.cycle.rounds.start",
  "read_.engine.cycle.rounds.status",
  "read_.engine.cycle.rounds.output",
  "write.engine.cycle.rounds.stop",
]);

const legacyOrchestrationTools = new Set([
  "write.browser.session.cmcp.go",
  "write.browser.chatgpt.chat.adopt_go",
  "read_.browser.chatgpt.watch.next",
  "read_.browser.chatgpt.run.loop.plan",
  "read_.browser.chatgpt.run.loop.step",
  "read_.browser.chatgpt.run.loop.step.summary",
  "read_.browser.chatgpt.run.loop.auto.summary",
  "write.browser.session.run.loop.daemon.start",
  "write.engine.cycle.step",
  "write.engine.cycle.run",
  "write.engine.task.enqueue",
  "write.engine.worker.tick",
  "write.engine.chat.bind",
  "write.engine.answer.capture",
  "write.engine.gateway.decide",
  "write.engine.reply.draft",
  "write.engine.reply.submit",
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
  const legacyEngineTimeoutMs = readPositiveIntEnv("CONSOLE_MCP_BRIDGE_ENGINE_TIMEOUT_MS", 300000);
  const recipeTimeoutMs = readPositiveIntEnv("CONSOLE_MCP_BRIDGE_RECIPE_TIMEOUT_MS", legacyEngineTimeoutMs);
  const boundedRecipeTimeoutMs = Math.min(recipeTimeoutMs, 300000);
  const longToolPrefixes = [
    "write.browser.session.cmcp.go",
    "write.browser.chatgpt.chat.adopt_go",
  ];
  return longToolPrefixes.some((prefix) => toolName === prefix || toolName.startsWith(`${prefix}.`)) ? boundedRecipeTimeoutMs : defaultTimeoutMs;
}

async function main() {
  if (process.argv.length === 3 && process.argv[2] === "--runtime-check") {
    const { version } = await loadConsoleMcpSdk();
    process.stdout.write(JSON.stringify({
      ok: true, status: "LOOPING_CONSOLE_MCP_SDK_READY", sdkVersion: version,
      connected: false, dispatched: false
    }) + "\n");
    return;
  }
  const args = parseArgs(process.argv);
  const payloadPath = args.payload;
  const resultPath = args.result;
  if (!payloadPath) throw new Error("--payload is required");
  if (!resultPath) throw new Error("--result is required");

  const toolCall = await readToolCall(payloadPath);
  if (!toolAllowed(toolCall)) {
    throw new Error(`console-mcp bridge tool not allowed: ${toolCall.name}`);
  }
  if (m5AtomicWriteTools.has(toolCall.name)) {
    const admission = validateM5AtomicInvocation(toolCall);
    if (!admission.ok) throw new Error(admission.status);
  }

  const token = process.env.CONSOLE_MCP_BEARER_TOKEN ?? "";
  const placeholderTokens = new Set(["dev", "test", "changeme", "change-me", "dev-token", "local-dev-token", "console-mcp-dev-token"]);
  if (!token.trim() || placeholderTokens.has(token.trim().toLowerCase())) {
    throw new Error("CONSOLE_MCP_BEARER_TOKEN_MISSING_OR_PLACEHOLDER");
  }
  const endpoint = new URL(process.env.CONSOLE_MCP_ENDPOINT ?? "http://127.0.0.1:3335/mcp");
  if (endpoint.href !== "http://127.0.0.1:3335/mcp") {
    throw new Error("CONSOLE_MCP_ENDPOINT_NOT_RUNNER_PROFILE");
  }
  const { Client, StreamableHTTPClientTransport, StreamableHTTPError, UnauthorizedError } = await loadConsoleMcpSdk();
  const transport = new StreamableHTTPClientTransport(endpoint, {
    requestInit: { headers: { Authorization: `Bearer ${token}` } },
  });
  const client = new Client({ name: "chatgpt-loop-runner-bridge", version: "1.0.0" });

  try {
    try {
      await client.connect(transport);
    } catch (error) {
      // Token rotation is safe only before any tool dispatch. Never classify
      // an error from callTool (or a result write/close failure) as retryable.
      if (error instanceof UnauthorizedError || (error instanceof StreamableHTTPError && error.code === 401)) {
        process.stderr.write("CONSOLE_MCP_HANDSHAKE_UNAUTHORIZED_NO_DISPATCH\n");
        process.exitCode = 77;
        return;
      }
      throw error;
    }
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
