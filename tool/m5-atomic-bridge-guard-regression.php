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
assert(str_contains($source, 'const allowedTools = new Set([...atomicTools, ...legacyOrchestrationTools]);'));

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
assert(str_contains($defaultAtomicBlock, 'console.read_.runtime.mobile_edge.server.status'));
assert(str_contains($defaultAtomicBlock, 'console.read_.runtime.visual_gallery.server.status'));

$legacyStart = strpos($source, 'const legacyOrchestrationTools = new Set([');
$legacyEnd = strpos($source, 'const allowedTools =', $legacyStart === false ? 0 : $legacyStart);
assert($legacyStart !== false && $legacyEnd !== false && $legacyEnd > $legacyStart);
$legacyBlock = substr($source, $legacyStart, $legacyEnd - $legacyStart);
assert(!str_contains($legacyBlock, 'console.write.browser.session.open'));

fwrite(STDOUT, "OK: M5 atomic bridge guard regression passed.\n");
