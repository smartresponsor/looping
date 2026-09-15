<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowDecisionProjector;
use App\Service\ChatGptLoopShadowRecoveryProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowRecoveryProjector.php';

$options = getopt('', ['fixture::', 'output-dir::']);
$fixturePath = isset($options['fixture']) && is_string($options['fixture'])
    ? $options['fixture']
    : dirname(__DIR__) . '/fixtures/orchestration-historical-evidence.json';
$outputDir = isset($options['output-dir']) && is_string($options['output-dir'])
    ? $options['output-dir']
    : dirname(__DIR__) . '/var/runner/evidence/historical';

$fixture = json_decode((string) file_get_contents($fixturePath), true, 512, JSON_THROW_ON_ERROR);
$entries = is_array($fixture['entries'] ?? null) ? $fixture['entries'] : [];
if (!is_dir($outputDir) && !mkdir($outputDir, 0777, true) && !is_dir($outputDir)) {
    throw new RuntimeException('Unable to create historical evidence output directory.');
}

$decisionProjector = new ChatGptLoopShadowDecisionProjector();
$recoveryProjector = new ChatGptLoopShadowRecoveryProjector();
$written = [];
$divergenceCount = 0;

foreach ($entries as $index => $entry) {
    if (!is_array($entry)) continue;
    $coverageClass = is_string($entry['coverageClass'] ?? null) ? $entry['coverageClass'] : 'unknown';
    $projector = is_string($entry['projector'] ?? null) ? $entry['projector'] : '';
    $snapshot = is_array($entry['snapshot'] ?? null) ? $entry['snapshot'] : [];
    $expected = is_array($entry['expected'] ?? null) ? $entry['expected'] : [];
    $provenance = is_array($entry['provenance'] ?? null) ? $entry['provenance'] : [];
    $actual = [];
    $shadowRecovery = null;
    $shadowDecision = null;

    if ($projector === 'recovery') {
        $shadowRecovery = $recoveryProjector->project(['task' => $snapshot]);
        $actual['recoveryClass'] = $shadowRecovery['recoveryClass'] ?? null;
    } elseif ($projector === 'decision') {
        $shadowDecision = $decisionProjector->project($snapshot);
        $actual['stopReason'] = $shadowDecision['stopReason'] ?? null;
    } else {
        throw new RuntimeException('Unsupported historical evidence projector: ' . $projector);
    }

    $differences = [];
    foreach ($expected as $key => $value) {
        if (($actual[$key] ?? null) !== $value) {
            $differences[$key] = ['authoritative' => $value, 'shadow' => $actual[$key] ?? null];
        }
    }
    $status = $differences === [] ? 'LIVE_SHADOW_PARITY_MATCH' : 'LIVE_SHADOW_PARITY_DIVERGENCE';
    if ($differences !== []) $divergenceCount++;

    $taskId = is_string($provenance['sourceTaskId'] ?? null) ? $provenance['sourceTaskId'] : 'unknown-task';
    $eventId = is_string($provenance['sourceEventId'] ?? null) ? $provenance['sourceEventId'] : 'event-' . $index;
    $artifact = [
        'schema' => 'chatgpt-loop-historical-shadow-parity-v1',
        'status' => $status,
        'authoritative' => false,
        'runtimeEffect' => 'none',
        'coverageClass' => $coverageClass,
        'capturedAt' => $provenance['sourceEventTs'] ?? gmdate('c'),
        'provenance' => $provenance,
        'normalizedTask' => ['task_id' => $taskId] + ($projector === 'recovery' ? $snapshot : []),
        'shadowRecovery' => $shadowRecovery,
        'shadowDecision' => $shadowDecision,
        'expected' => $expected,
        'actual' => $actual,
        'differences' => $differences,
    ];
    $safeName = preg_replace('/[^A-Za-z0-9._-]+/', '-', $coverageClass . '-' . $eventId);
    $file = $outputDir . '/' . $safeName . '.parity.json';
    file_put_contents($file, json_encode($artifact, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
    $written[] = $file;
}

fwrite(STDOUT, json_encode([
    'ok' => $divergenceCount === 0,
    'status' => $divergenceCount === 0 ? 'HISTORICAL_SHADOW_EVIDENCE_IMPORTED' : 'HISTORICAL_SHADOW_EVIDENCE_DIVERGENCE',
    'fixture' => $fixturePath,
    'outputDir' => $outputDir,
    'artifactCount' => count($written),
    'divergenceCount' => $divergenceCount,
    'written' => $written,
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
exit($divergenceCount === 0 ? 0 : 1);
