<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowDecisionProjector;
use App\Service\ChatGptLoopShadowStateProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowStateProjector.php';

$options = getopt('', ['input:', 'output:']);
$inputPath = isset($options['input']) ? (string) $options['input'] : '';
$outputPath = isset($options['output']) ? (string) $options['output'] : '';
if ($inputPath === '' || $outputPath === '') {
    fwrite(STDERR, "Usage: php tool/shadow-state-parity-capture.php --input=<receipt.json> --output=<artifact.json>\n");
    exit(2);
}
$raw = file_get_contents($inputPath);
if ($raw === false) {
    throw new RuntimeException('Unable to read input receipt.');
}
$input = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
if (!is_array($input)) {
    throw new RuntimeException('Input receipt must decode to an object.');
}
$projector = new ChatGptLoopShadowStateProjector(new ChatGptLoopShadowDecisionProjector());
$shadow = $projector->project($input);
$authoritative = is_array($input['task'] ?? null) ? $input['task'] : [];
$parity = $projector->compare($authoritative, $shadow);
$artifact = [
    'schemaVersion' => 1,
    'status' => 'SHADOW_STATE_PARITY_ARTIFACT',
    'authoritative' => false,
    'capturedAt' => gmdate('c'),
    'sourceReceipt' => realpath($inputPath) ?: $inputPath,
    'shadow' => $shadow,
    'parity' => $parity,
];
$directory = dirname($outputPath);
if (!is_dir($directory) && !mkdir($directory, 0777, true) && !is_dir($directory)) {
    throw new RuntimeException('Unable to create parity artifact directory.');
}
$json = json_encode($artifact, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL;
if (file_put_contents($outputPath, $json) === false) {
    throw new RuntimeException('Unable to write parity artifact.');
}
fwrite(STDOUT, json_encode(['ok' => true, 'status' => $parity['status'], 'output' => $outputPath], JSON_THROW_ON_ERROR) . PHP_EOL);
