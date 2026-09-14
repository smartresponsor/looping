<?php

declare(strict_types=1);

use App\Service\ChatGptLoopCompletionVerificationContract;

require dirname(__DIR__) . '/src/Service/ChatGptLoopCompletionVerificationContract.php';

$contract = new ChatGptLoopCompletionVerificationContract();

$description = $contract->describe(['mutation_policy' => 'read_only']);
assert($description['authoritative'] === false);
assert($description['requirements'] !== []);
assert($description['budgetExhaustionIsCompletion'] === false);

$verified = $contract->evaluateReceipt([
    'status' => 'ENGINE_COMPLETION_FACTS_AND_GATES_VERIFIED',
    'current_worktree_fingerprint' => str_repeat('a', 64),
    'current_head' => str_repeat('b', 40),
    'git_diff_check' => 'PASS',
    'gate_results' => [['ok' => true, 'check_name' => 'composer_validate']],
    'applicability' => ['required' => false],
    'runtime_verification' => ['required' => false, 'ok' => true],
    'behavioral_evidence' => ['ok' => true],
]);
assert($verified['verified'] === true);

$failed = $contract->evaluateReceipt([
    'status' => 'ENGINE_COMPLETION_FACTS_AND_GATES_VERIFIED',
    'current_worktree_fingerprint' => str_repeat('a', 64),
    'current_head' => str_repeat('b', 40),
    'git_diff_check' => 'PASS',
    'gate_results' => [['ok' => false, 'check_name' => 'test']],
    'applicability' => ['required' => false],
]);
assert($failed['verified'] === false);
assert($failed['failedGateCount'] === 1);

fwrite(STDOUT, "OK: completion verification contract regression passed.\n");
