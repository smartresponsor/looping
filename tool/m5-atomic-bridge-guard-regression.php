<?php

declare(strict_types=1);

$root = dirname(__DIR__);
$source = (string) file_get_contents($root . '/tool/runner-console-mcp-bridge.mjs');

assert(str_contains($source, 'const m5AtomicWriteTools = new Set(['));
assert(str_contains($source, '"console.write.browser.session.open"'));
assert(str_contains($source, '"console.write.browser.session.input.draft"'));
assert(str_contains($source, '"console.write.browser.session.submit"'));
assert(str_contains($source, 'process.env.CHATGPT_LOOP_M5_ATOMIC_TRANSPORT_ENABLED === "1"'));
assert(str_contains($source, 'toolCall.authorityMode === "m5_opt_in"'));
assert(str_contains($source, 'const durableAsyncTools = new Set(['));
$engineWritePrefix = 'console.' . 'write.engine.';
$engineReadPrefix = 'console.' . 'read_.engine.';
assert(str_contains($source, '"' . $engineWritePrefix . 'cycle.rounds.start"'));
assert(str_contains($source, '"' . $engineReadPrefix . 'cycle.rounds.status"'));
assert(str_contains($source, '"' . $engineReadPrefix . 'cycle.rounds.output"'));
assert(str_contains($source, '"' . $engineWritePrefix . 'cycle.rounds.stop"'));
assert(str_contains($source, 'const allowedTools = new Set([...atomicTools, ...durableAsyncTools, ...legacyOrchestrationTools]);'));
assert(str_contains($source, 'return "durable_async";'));

$atomicStart = strpos($source, 'const atomicTools = new Set([');
$atomicEnd = strpos($source, 'const m5AtomicWriteTools = new Set([', $atomicStart === false ? 0 : $atomicStart);
assert($atomicStart !== false && $atomicEnd !== false && $atomicEnd > $atomicStart);
$defaultAtomicBlock = substr($source, $atomicStart, $atomicEnd - $atomicStart);
assert(!str_contains($defaultAtomicBlock, 'console.write.browser.session.open'));
assert(!str_contains($defaultAtomicBlock, 'console.write.browser.session.input.draft'));
assert(!str_contains($defaultAtomicBlock, 'console.write.browser.session.submit'));
assert(str_contains($defaultAtomicBlock, 'console.read_.repo.git.branch.status'));
assert(str_contains($defaultAtomicBlock, 'console.read_.repo.implementation.run.capture'));
assert(str_contains($defaultAtomicBlock, 'console.read_.repo.gate.check.run'));
assert(str_contains($defaultAtomicBlock, 'console.read_.repo.file.bundle.read'));
assert(str_contains($defaultAtomicBlock, 'console.read_.runtime.php.server.status'));
assert(str_contains($defaultAtomicBlock, 'console.read_.runtime.mobile.edge.server.status'));
assert(str_contains($defaultAtomicBlock, 'console.read_.runtime.visual.gallery.server.status'));

$legacyStart = strpos($source, 'const legacyOrchestrationTools = new Set([');
$legacyEnd = strpos($source, 'const allowedTools =', $legacyStart === false ? 0 : $legacyStart);
assert($legacyStart !== false && $legacyEnd !== false && $legacyEnd > $legacyStart);
$legacyBlock = substr($source, $legacyStart, $legacyEnd - $legacyStart);
assert(!str_contains($legacyBlock, 'console.write.browser.session.open'));

$timeoutStart = strpos($source, 'function resolveToolRequestTimeoutMs');
$timeoutEnd = strpos($source, 'async function main', $timeoutStart === false ? 0 : $timeoutStart);
assert($timeoutStart !== false && $timeoutEnd !== false && $timeoutEnd > $timeoutStart);
$timeoutBlock = substr($source, $timeoutStart, $timeoutEnd - $timeoutStart);
assert(!str_contains($timeoutBlock, '"' . $engineWritePrefix . 'cycle.run"'));
assert(!str_contains($timeoutBlock, '"' . $engineWritePrefix . 'cycle.rounds.run"'));
$cmcpGoName = 'console.' . 'write.browser.session.' . 'cmcp.go';
$adoptGoName = 'console.' . 'write.browser.chatgpt.chat.' . 'adopt_go';
assert(str_contains($timeoutBlock, '"' . $cmcpGoName . '"'));
assert(str_contains($timeoutBlock, '"' . $adoptGoName . '"'));

fwrite(STDOUT, "OK: M5 atomic bridge guard regression passed.\n");
