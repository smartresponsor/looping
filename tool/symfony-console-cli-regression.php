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

// Preserve established JSON error/exit-code contracts for supported options.
[$code, $out, $err] = $run([
    'chatgpt-loop:adopt-current-chat',
    '--component=viewing',
    '--plan-only=1',
]);
$error = json_decode($err, true, 512, JSON_THROW_ON_ERROR);
if ($code !== 1 || ($error['status'] ?? null) !== 'ADOPT_CURRENT_CHAT_REJECTED'
    || ($error['error'] ?? null) !== 'The --location option is required.') {
    throw new RuntimeException('Adopt missing-location compatibility failed.');
}

[$code, $out, $err] = $run([
    'chatgpt-loop:run', '--plan-only=1',
]);
$error = json_decode($err, true, 512, JSON_THROW_ON_ERROR);
if ($code !== 1 || ($error['status'] ?? null) !== 'FAILED'
    || ($error['error'] ?? null) !== 'The --task option is required.') {
    throw new RuntimeException('Run missing-task compatibility failed.');
}

// All actual Looping continuation and evidence flags must be accepted by Symfony.
// These args come from runner-adapter.ps1 and PHP services; this plan-only test
// intentionally does not submit a browser prompt or start the PowerShell runner.
$legacyContinuationOptions = [
    'dispatch-status=accepted',
    'external-task-id=task_fixture',
    'external-chat-id=11111111-1111-1111-1111-111111111111',
    'external-target-id=target_fixture',
    'response-task-id=task_fixture',
    'response-chat-id=11111111-1111-1111-1111-111111111111',
    'response-target-id=target_fixture',
    'ask-verdict=continue',
    'ask-next-action=go',
    'ask-message-to-chat=ok',
    'ask-policy-references=none',
    'ask-risks=none',
    'repo-before-head=abc',
    'repo-after-head=def',
    'repo-changed-files=0',
    'repo-diff-stat=none',
    'repo-dirty-before=0',
    'repo-dirty-after=0',
    'gate-available=1',
    'gate-passed=1',
    'gate-failed=0',
];
[$code, $out, $err] = $run(array_merge([
    'chatgpt-loop:run', '--task=!diagnose', '--mode=diagnostic', '--plan-only=1',
], array_map(static fn (string $flag): string => '--' . $flag, $legacyContinuationOptions)));
$payload = json_decode($out, true, 512, JSON_THROW_ON_ERROR);
if ($code !== 0 || ($payload['status'] ?? null) !== 'PLAN_ONLY_READY') {
    throw new RuntimeException("Legacy continuation flags rejected: $err $out");
}

// Intentional strictness: Symfony rejects unknown flags that the old dispatcher silently ignored.
[$code, $out, $err] = $run([
    'chatgpt-loop:adopt-current-chat',
    '--component=viewing',
    '--location=@viewing',
    '--plan-only=1',
    '--unknown=1',
]);
if ($code === 0 || !str_contains($err . $out, 'unknown')) {
    throw new RuntimeException('Unknown CLI option must be rejected.');
}

fwrite(STDOUT, "LOOPING_SYMFONY_CONSOLE_CLI_REGRESSION_PASS\n");
