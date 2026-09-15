<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowParityEvidence;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowParityEvidence.php';

$options = getopt('', ['dir::', 'output::']);
$directory = isset($options['dir']) && is_string($options['dir'])
    ? $options['dir']
    : dirname(__DIR__) . '/var/runner/task-bank/parity';
$outputPath = isset($options['output']) && is_string($options['output']) ? $options['output'] : null;

$artifacts = [];
if (is_dir($directory)) {
    $paths = glob(rtrim($directory, '/\\') . '/*.parity.json') ?: [];
    sort($paths, SORT_STRING);
    foreach ($paths as $path) {
        $decoded = json_decode((string) file_get_contents($path), true);
        if (is_array($decoded)) {
            $artifacts[] = $decoded;
        }
    }
}

$summary = (new ChatGptLoopShadowParityEvidence())->summarize($artifacts);
$summary['schema'] = 'chatgpt-loop-m4-parity-evidence-v1';
$summary['capturedAt'] = gmdate('c');
$summary['sourceDirectory'] = realpath($directory) ?: $directory;
$json = json_encode($summary, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL;

if ($outputPath !== null) {
    $parent = dirname($outputPath);
    if (!is_dir($parent) && !mkdir($parent, 0777, true) && !is_dir($parent)) {
        throw new RuntimeException('Unable to create M4 parity evidence output directory.');
    }
    file_put_contents($outputPath, $json);
}

fwrite(STDOUT, $json);
