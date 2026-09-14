<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowDecisionProjector;
use App\Service\ChatGptLoopShadowStateProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowStateProjector.php';

$projector = new ChatGptLoopShadowStateProjector(new ChatGptLoopShadowDecisionProjector());

$task = [
    'task_id' => 'engine-test-1',
    'component' => 'carting',
    'workspace_path' => 'D:\\PhpstormProjects\\www\\Carting',
    'chat_id' => '11111111-1111-1111-1111-111111111111',
    'target_id' => 'target-1',
    'status' => 'running',
    'phase_key' => 'implementation',
    'cycle_round_index' => 2,
    'auto_iteration_count' => 2,
    'max_auto_iterations' => 5,
    'decision_status' => 'continue',
    'cycle_progress_fingerprint' => 'abc',
    'cycle_progress_repeat_count' => 1,
    'baseline_assistant_hash' => 'base',
    'last_assistant_hash' => 'last',
];
$shadow = $projector->project(['task' => $task, 'round' => ['round_stop_reason' => 'complete']]);
assert($shadow['authoritative'] === false);
assert($shadow['identity']['taskId'] === 'engine-test-1');
assert($shadow['lifecycle']['remainingIterations'] === 3);
assert($shadow['decision']['continue'] === true);

$match = $projector->compare($task, $shadow);
assert($match['ok'] === true);
assert($match['status'] === 'SHADOW_STATE_PARITY_MATCH');

$divergent = $shadow;
$divergent['identity']['chatId'] = '22222222-2222-2222-2222-222222222222';
$diff = $projector->compare($task, $divergent);
assert($diff['ok'] === false);
assert($diff['status'] === 'SHADOW_STATE_PARITY_DIVERGENCE');
assert(isset($diff['differences']['chatId']));

$terminal = $projector->project([
    'task' => array_merge($task, ['decision_status' => 'done']),
    'round' => ['round_stop_reason' => 'completion_candidate'],
    'completion_verified' => true,
]);
assert($terminal['decision']['stopReason'] === 'decision_done_verified:done');
assert($terminal['decision']['terminal'] === true);

fwrite(STDOUT, "OK: shadow state parity regression passed.\n");
