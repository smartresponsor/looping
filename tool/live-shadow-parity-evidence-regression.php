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
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'actual' => ['stopReason' => 'decision_done_verified:done'], 'completionVerification' => ['verified' => true, 'status' => 'SHADOW_COMPLETION_VERIFIED', 'outcomeCode' => 'COMPLETION_ALL_CHECKS_VERIFIED']], 'completion'),
]);
assert($ready['status'] === 'M4_SHADOW_PARITY_EVIDENCE_READY');
assert($ready['m4EvidenceReady'] === true);
assert($ready['missingCoverage'] === []);
assert($ready['missingCompleteCoverage'] === []);
assert($ready['provenanceRejected'] === []);

$unverifiedCompletion = $evidence->summarize([
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'coverageClass' => 'completion', 'normalizedTask' => ['status' => 'completed', 'decision_status' => 'continue']], 'completed-without-proof'),
]);
assert(in_array('completion', $unverifiedCompletion['observedCoverage'], true));
assert(in_array('completion', $unverifiedCompletion['missingCompleteCoverage'], true));
assert($unverifiedCompletion['m4EvidenceReady'] === false);

$spoofedVerification = $evidence->summarize([
    $historical(['status' => 'LIVE_SHADOW_PARITY_MATCH', 'coverageClass' => 'completion', 'completionVerification' => ['verified' => true]], 'spoofed-boolean'),
]);
assert(in_array('completion', $spoofedVerification['missingCompleteCoverage'], true));
assert($spoofedVerification['m4EvidenceReady'] === false);

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


// Exercise the actual CLI capture boundary, including provenance binding and spoof rejection.
$inputPath = tempnam(sys_get_temp_dir(), 'loop-m4-in-');
$outputPath = tempnam(sys_get_temp_dir(), 'loop-m4-out-');
assert(is_string($inputPath) && is_string($outputPath));
$receipt = [
    'task_id' => 'engine-completion-1',
    'event_id' => 'event-completion-1',
        'event' => 'engine_execution_completed',
    'event_ts' => '2026-11-24T00:00:00Z',
    'status' => 'ENGINE_COMPLETION_FACTS_AND_GATES_VERIFIED',
    'current_worktree_fingerprint' => str_repeat('a', 64),
    'current_head' => str_repeat('b', 40),
    'git_diff_check' => 'PASS',
    'gate_results' => [['ok' => true, 'check_name' => 'composer_validate']],
    'applicability' => ['required' => false],
    'runtime_verification' => ['required' => false, 'ok' => true],
];
$payload = [
    'snapshot' => ['task' => ['task_id' => 'engine-completion-1', 'status' => 'completed', 'decision_status' => 'done'], 'completion_verified' => true],
    'authoritative' => ['continue' => false, 'terminal' => true, 'decisionStatus' => 'done'],
    'provenance' => [
        'origin' => 'console_engine_history',
        'immutableReceipt' => true,
        'sourceTaskId' => 'engine-completion-1',
        'sourceEventId' => 'event-completion-1',
        'sourceEventTs' => '2026-11-24T00:00:00Z',
    ],
    'completion_receipt' => $receipt,
];
$capture = static function (array $input) use ($inputPath, $outputPath): array {
    file_put_contents($inputPath, json_encode($input, JSON_THROW_ON_ERROR));
    $command = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/live-shadow-parity-capture.php')
        . ' --input=' . escapeshellarg($inputPath) . ' --output=' . escapeshellarg($outputPath);
    exec($command, $lines, $exitCode);
    assert($exitCode === 0);
    return json_decode((string) file_get_contents($outputPath), true, 512, JSON_THROW_ON_ERROR);
};
try {
    $validCapture = $capture($payload);
    assert($validCapture['completionVerification']['verified'] === true);
    $payload['provenance']['sourceEventId'] = 'event-unrelated';
    $invalidCapture = $capture($payload);
    assert($invalidCapture['completionVerification']['verified'] === false);
    assert($invalidCapture['completionVerification']['outcomeCode'] === 'COMPLETION_RECEIPT_PROVENANCE_MISMATCH');
    unset($payload['completion_receipt']);
    $spoofedCapture = $capture($payload);
    assert(!isset($spoofedCapture['completionVerification']));
    assert(($spoofedCapture['shadowState']['decision']['stopReason'] ?? null) !== 'decision_done_verified:done');
} finally {
    unlink($inputPath);
    unlink($outputPath);
}

fwrite(STDOUT, "OK: M4 live shadow parity evidence regression passed.\n");
