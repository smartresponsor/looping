<?php

declare(strict_types=1);

/**
 * #120 Symfony Console CLI contract check. No browser submissions.
 * Run after composer install with PHP 8.4+.
 */
$root = dirname(__DIR__);
$run = static function (array $args) use ($root): array {
    $process = proc_open(array_merge([PHP_BINARY, $root . '/bin/console'], $args),
        [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, $root);
    if (!is_resource($process)) {
        throw new RuntimeException('Cannot execute Symfony Console command.');
    }
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    return [proc_close($process), trim((string) $stdout), trim((string) $stderr)];
};

foreach (['chatgpt-loop:run', 'chatgpt-loop:adopt-current-chat', 'chatgpt-loop:contract', 'chatgpt-loop:dispatcher-contract'] as $name) {
    [$code, $out, $err] = $run([$name, '--help']);
    if ($code !== 0 || !str_contains($out, $name)) {
        throw new RuntimeException("Symfony help failed for $name: $err $out");
    }
}

[$code, $out, $err] = $run([
    'chatgpt-loop:adopt-current-chat',
    '--component=viewing',
    '--location=@viewing-investigation',
    '--max-auto-iterations=3',
    '--plan-only=1',
]);
$payload = json_decode($out, true, 512, JSON_THROW_ON_ERROR);
if ($code !== 0 || ($payload['status'] ?? null) !== 'ADOPT_CURRENT_CHAT_PLAN_READY'
    || ($payload['contract']['existingLocation'] ?? null) !== '@viewing-investigation') {
    throw new RuntimeException("Adoption compatibility failed: $err $out");
}

foreach (['chatgpt-loop:contract', 'chatgpt-loop:dispatcher-contract'] as $name) {
    [$code, $out, $err] = $run([$name]);
    json_decode($out, true, 512, JSON_THROW_ON_ERROR);
    if ($code !== 0) throw new RuntimeException("Contract command failed: $name $err");
}

fwrite(STDOUT, "LOOPING_SYMFONY_CONSOLE_CLI_REGRESSION_PASS\n");
