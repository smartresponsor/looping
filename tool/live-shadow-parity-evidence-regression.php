<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowParityEvidence;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowParityEvidence.php';

$evidence = new ChatGptLoopShadowParityEvidence();
$historical = static function (array $artifact, string $suffix): array {
    $artifact['provenance'] = [
        'origin' => 'console_engine_history',
        'immutableReceipt' => true,
        'sourceTaskId' => 'engine-history-' . $suffix,
        'sourceEventId' => 'event-history-' . $suffix,
        'sourceEventTs' => '2026-09-14T20:00:00.000Z',
    ];
    return $artifact;
};

$empty = $evidence->summarize([]);
assert($empty['status'] === 'M4_SHADOW_PARITY_EVIDENCE_INCOMPLETE');
assert($empty['m4EvidenceReady'] === false);

$fixtureOnly = $evidence->summarize([
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['continue' => true]],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'normalizedTask' => ['status' => 'blocked'], 'actual' => ['recoveryClass' => 'rebind_chat']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['recoveryClass' => 'wait_rate_limit_cooldown']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['recoveryClass' => 'resubmit_orphaned_answer']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'human_decision_required']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'stalled_no_semantic_progress']],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'decision_done_verified:done']],
]);
assert($fixtureOnly['status'] === 'M4_SHADOW_PARITY_EVIDENCE_INCOMPLETE');
assert($fixtureOnly['m4EvidenceReady'] === false);
assert(count($fixtureOnly['provenanceRejected']) === 7);

$ready = $evidence->summarize([
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['continue' => true]], 'continue'),
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'normalizedTask' => ['status' => 'blocked'], 'actual' => ['recoveryClass' => 'rebind_chat']], 'blocked-retry'),
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['recoveryClass' => 'wait_rate_limit_cooldown']], 'rate-limit'),
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['recoveryClass' => 'resubmit_orphaned_answer']], 'orphan'),
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'human_decision_required']], 'human'),
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'stalled_no_semantic_progress']], 'stall'),
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'decision_done_verified:done']], 'completion'),
]);
assert($ready['status'] === 'M4_SHADOW_PARITY_EVIDENCE_READY');
assert($ready['m4EvidenceReady'] === true);
assert($ready['missingCoverage'] === []);
assert($ready['missingCompleteCoverage'] === []);
assert($ready['provenanceRejected'] === []);

$partialRetry = $evidence->summarize([
    ['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['continue' => true]],
    ['status' => 'LIVE_SHADOW_PARITY_MATCH_PARTIAL', 'coverageClass' => 'retry', 'normalizedTask' => ['status' => 'blocked'], 'actual' => ['recoveryClass' => 'rebind_chat']],
]);
assert(in_array('retry', $partialRetry['observedCoverage'], true));
assert(!in_array('retry', $partialRetry['completeCoverage'], true));
assert(!in_array('retry', $partialRetry['missingCoverage'], true));
assert(in_array('retry', $partialRetry['missingCompleteCoverage'], true));
assert($partialRetry['m4EvidenceReady'] === false);

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
