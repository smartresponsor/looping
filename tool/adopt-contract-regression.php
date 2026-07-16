<?php

declare(strict_types=1);

use App\Command\ChatGptLoopAdoptCurrentChatCommand;

require dirname(__DIR__) . '/src/Command/ChatGptLoopAdoptCurrentChatCommand.php';

$root = dirname(__DIR__);

$runPlan = static function (array $arguments) use ($root): array {
    $command = array_merge([PHP_BINARY, $root . '/bin/console', 'chatgpt-loop:adopt-current-chat'], $arguments);
    $descriptor = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $process = proc_open($command, $descriptor, $pipes, $root);
    if (!is_resource($process)) {
        throw new RuntimeException('Unable to start adoption plan command.');
    }
    $output = stream_get_contents($pipes[1]);
    $error = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($process);
    if ($exitCode !== 0) {
        throw new RuntimeException('Plan command failed: ' . $error . $output);
    }

    return json_decode($output, true, 512, JSON_THROW_ON_ERROR);
};

$location = $runPlan([
    '--component=viewing',
    '--location=@viewing-cleaner-investigation',
    '--max-auto-iterations=3',
    '--plan-only=1',
]);
assert($location['contract']['existingLocation'] === '@viewing-cleaner-investigation');
assert($location['contract']['chatId'] === null);
assert($location['contract']['resolverOwner'] === 'console-mcp');

$chatId = '11111111-1111-1111-1111-111111111111';
$url = $runPlan([
    '--component=viewing',
    '--current-chat-url=https://chatgpt.com/c/' . $chatId,
    '--max-auto-iterations=3',
    '--plan-only=1',
]);
assert($url['contract']['chatId'] === $chatId);

$rawId = $runPlan([
    '--component=viewing',
    '--location=' . strtoupper($chatId),
    '--max-auto-iterations=3',
    '--plan-only=1',
]);
assert($rawId['contract']['chatId'] === $chatId);

$runner = file_get_contents($root . '/tool/runner-adopt-current-chat.ps1');
$taskBank = file_get_contents($root . '/tool/runner-task-bank-loop.ps1');
assert(is_string($runner) && str_contains($runner, "tool = 'console.write.browser.chatgpt.chat.adopt_go'"));
assert(is_string($runner) && str_contains($runner, '$Arguments.locator = $ExistingLocation'));
assert(is_string($taskBank) && str_contains($taskBank, '[guid]::NewGuid().ToString'));

fwrite(STDOUT, "OK: adopt location contract regression passed.\n");
