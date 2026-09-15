<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowParityEvidence;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowParityEvidence.php';

$evidence = new ChatGptLoopShadowParityEvidence();

$empty = $evidence->summarize([]);
assert($empty['status'] === 'M4_SHADOW_PARITY_EVIDENCE_INCOMPLETE');
assert($empty['m4EvidenceReady'] === false);

$ready = $evidence->summarize([
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['continue' => true]],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'normalizedTask' => ['status' => 'blocked'], 'actual' => ['recoveryClass' => 'rebind_chat']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['recoveryClass' => 'wait_rate_limit_cooldown']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['recoveryClass' => 'resubmit_orphaned_answer']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'human_decision_required']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'stalled_no_semantic_progress']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'decision_done_verified:done']],
]);
assert($ready['status'] === 'M4_SHADOW_PARITY_EVIDENCE_READY');
assert($ready['m4EvidenceReady'] === true);
assert($ready['missingCoverage'] === []);

$historicalRepresentationOnly = $evidence->summarize([
    ['status' => 'LIVE_SHADOW_PARITY_DIVERGENCE', 'actual' => ['continue' => true], 'differences' => ['decisionStatus' => ['authoritative' => 'ANSWER_STABLE', 'shadow' => 'answer stable']]],
]);
assert($historicalRepresentationOnly['status'] === 'M4_SHADOW_PARITY_EVIDENCE_INCOMPLETE');
assert($historicalRepresentationOnly['counts']['match'] === 1);
assert(in_array('completion', $historicalRepresentationOnly['missingCoverage'], true));

$divergent = $evidence->summarize([
    ['status' => 'LIVE_SHADOW_PARITY_MATCH'],
    ['status' => 'LIVE_SHADOW_PARITY_DIVERGENCE', 'normalizedTask' => ['task_id' => 'task-2'], 'differences' => ['stopReason' => ['authoritative' => 'done', 'shadow' => 'continue']]],
]);
assert($divergent['status'] === 'M4_SHADOW_PARITY_EVIDENCE_DIVERGENCE');
assert($divergent['ok'] === false);
assert($divergent['m4EvidenceReady'] === false);
assert(count($divergent['divergences']) === 1);

fwrite(STDOUT, "OK: M4 live shadow parity evidence regression passed.\n");
