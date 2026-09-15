<?php

declare(strict_types=1);

use App\Service\ChatGptLoopActionMarkerRouter;
use App\Service\ChatGptLoopOrchestrationReceiptNormalizer;
use App\Service\ChatGptLoopShadowDecisionProjector;
use App\Service\ChatGptLoopShadowParityEvaluator;
use App\Service\ChatGptLoopShadowRecoveryProjector;
use App\Service\ChatGptLoopShadowStateProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopCleanupSignalParser.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopActionMarkerRouter.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopOrchestrationReceiptNormalizer.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowStateProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowRecoveryProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowParityEvaluator.php';

$options = getopt('', ['input:', 'output:']);
$inputPath = $options['input'] ?? null;
$outputPath = $options['output'] ?? null;
if (!is_string($inputPath) || !is_string($outputPath)) {
    fwrite(STDERR, "Usage: php tool/live-shadow-parity-capture.php --input=<receipt.json> --output=<artifact.json>\n");
    exit(2);
}

$payload = json_decode(file_get_contents($inputPath), true, 512, JSON_THROW_ON_ERROR);
$snapshot = is_array($payload['snapshot'] ?? null) ? $payload['snapshot'] : $payload;
$assistantText = is_string($snapshot['assistant_text'] ?? null) ? $snapshot['assistant_text'] : '';
$semanticRoute = (new ChatGptLoopActionMarkerRouter())->classify($assistantText);
if (!isset($snapshot['decision_status']) && (!isset($snapshot['task']) || !is_array($snapshot['task']) || !isset($snapshot['task']['decision_status']))) {
    $snapshot['decision_status'] = $semanticRoute['marker'];
}
$evaluator = new ChatGptLoopShadowParityEvaluator(
    new ChatGptLoopOrchestrationReceiptNormalizer(),
    new ChatGptLoopShadowStateProjector(new ChatGptLoopShadowDecisionProjector()),
    new ChatGptLoopShadowRecoveryProjector(),
);
$artifact = $evaluator->evaluate(
    $snapshot,
    is_array($payload['authoritative'] ?? null) ? $payload['authoritative'] : [],
);
$artifact['semanticRoute'] = $semanticRoute;
$artifact['provenance'] = is_array($payload['provenance'] ?? null) ? $payload['provenance'] : [];
$artifact['schema'] = 'chatgpt-loop-live-shadow-parity-v1';
$artifact['capturedAt'] = gmdate('c');
file_put_contents($outputPath, json_encode($artifact, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
fwrite(STDOUT, json_encode(['ok' => true, 'status' => 'LIVE_SHADOW_PARITY_ARTIFACT_WRITTEN', 'artifactStatus' => $artifact['status'], 'output' => $outputPath], JSON_THROW_ON_ERROR) . PHP_EOL);
