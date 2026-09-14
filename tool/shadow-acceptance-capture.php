<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowAcceptanceProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowAcceptanceProjector.php';

$options = getopt('', ['input:', 'output:']);
$inputPath = $options['input'] ?? null;
$outputPath = $options['output'] ?? null;
if (!is_string($inputPath) || !is_string($outputPath)) {
    fwrite(STDERR, "Usage: php tool/shadow-acceptance-capture.php --input=<receipt.json> --output=<artifact.json>\n");
    exit(2);
}

$input = json_decode(file_get_contents($inputPath), true, 512, JSON_THROW_ON_ERROR);
$artifact = (new ChatGptLoopShadowAcceptanceProjector())->project($input);
$artifact['schema'] = 'chatgpt-loop-shadow-acceptance-v1';
$artifact['capturedAt'] = gmdate('c');
file_put_contents($outputPath, json_encode($artifact, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
fwrite(STDOUT, json_encode([
    'ok' => true,
    'status' => 'SHADOW_ACCEPTANCE_ARTIFACT_WRITTEN',
    'taskComplete' => $artifact['taskAcceptance']['complete'],
    'output' => $outputPath,
], JSON_THROW_ON_ERROR) . PHP_EOL);
