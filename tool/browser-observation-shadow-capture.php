<?php

declare(strict_types=1);

use App\Service\ChatGptLoopBrowserObservationProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopBrowserObservationProjector.php';

$options = getopt('', ['input:', 'output:']);
$inputPath = $options['input'] ?? null;
$outputPath = $options['output'] ?? null;
if (!is_string($inputPath) || !is_string($outputPath)) {
    fwrite(STDERR, "Usage: php tool/browser-observation-shadow-capture.php --input=<receipt.json> --output=<artifact.json>\n");
    exit(2);
}

$input = json_decode(file_get_contents($inputPath), true, 512, JSON_THROW_ON_ERROR);
$artifact = (new ChatGptLoopBrowserObservationProjector())->project(
    is_array($input['probe'] ?? null) ? $input['probe'] : [],
    is_array($input['step'] ?? null) ? $input['step'] : [],
);
$authoritative = is_array($input['authoritative'] ?? null) ? $input['authoritative'] : [];
$differences = [];
foreach (['readyForCapture', 'quietEmptyBinding'] as $field) {
    if (array_key_exists($field, $authoritative) && is_bool($authoritative[$field]) && $artifact[$field] !== $authoritative[$field]) {
        $differences[$field] = ['authoritative' => $authoritative[$field], 'shadow' => $artifact[$field]];
    }
}
$artifact['parityStatus'] = $differences === [] ? 'SHADOW_BROWSER_OBSERVATION_PARITY_MATCH' : 'SHADOW_BROWSER_OBSERVATION_PARITY_DIVERGENCE';
$artifact['authoritativeReceipt'] = $authoritative;
$artifact['differences'] = $differences;
$artifact['schema'] = 'chatgpt-loop-shadow-browser-observation-v1';
$artifact['capturedAt'] = gmdate('c');
file_put_contents($outputPath, json_encode($artifact, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
fwrite(STDOUT, json_encode(['ok' => true, 'status' => $artifact['status'], 'parityStatus' => $artifact['parityStatus'], 'state' => $artifact['state'], 'output' => $outputPath], JSON_THROW_ON_ERROR) . PHP_EOL);
