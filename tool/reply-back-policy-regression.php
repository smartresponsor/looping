<?php

declare(strict_types=1);

use App\Service\ChatGptLoopReplyBackPolicy;

require dirname(__DIR__) . '/src/Service/ChatGptLoopReplyBackPolicy.php';

$policy = new ChatGptLoopReplyBackPolicy();

$readOnly = $policy->build('commit and continue', [
    'mutation_policy' => 'read_only',
    'git_commit_policy' => 'forbidden',
    'workspace_path' => 'D:\\Repo',
]);
assert($readOnly['marker'] === 'continue');
assert($readOnly['readOnly'] === true);
assert(str_contains($readOnly['text'], 'Do not modify'));
assert(str_contains($readOnly['text'], 'Git commit is FORBIDDEN'));

$sanitized = $policy->build('fix fail and continue', [
    'git_commit_policy' => 'forbidden',
    'decision_next_action' => 'Fix the failure, commit it, then continue.',
]);
assert($sanitized['marker'] === 'fix fail and continue');
assert(!str_contains($sanitized['text'], 'commit it'));
assert(str_contains($sanitized['text'], 'authorized workspace'));

fwrite(STDOUT, "OK: reply back policy regression passed.\n");
