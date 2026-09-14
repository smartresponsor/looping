<?php

declare(strict_types=1);

use App\Service\ChatGptLoopOrchestrationReceiptNormalizer;
use App\Service\ChatGptLoopShadowDecisionProjector;
use App\Service\ChatGptLoopShadowParityEvaluator;
use App\Service\ChatGptLoopShadowRecoveryProjector;
use App\Service\ChatGptLoopShadowStateProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopOrchestrationReceiptNormalizer.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowStateProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowRecoveryProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowParityEvaluator.php';

$evaluator = new ChatGptLoopShadowParityEvaluator(
    new ChatGptLoopOrchestrationReceiptNormalizer(),
    new ChatGptLoopShadowStateProjector(new ChatGptLoopShadowDecisionProjector()),
    new ChatGptLoopShadowRecoveryProjector(),
);

$match = $evaluator->evaluate([
    'task' => [
        'taskId' => 'loop-live-1',
        'name' => 'Vendoring',
        'workspacePath' => 'D:\\PhpstormProjects\\www\\Vendoring',
        'chatId' => '11111111-1111-1111-1111-111111111111',
        'targetId' => 'target-1',
        'status' => 'waiting_answer',
        'interactionCount' => 1,
        'maxInteractions' => 3,
        'attempt' => 0,
        'decisionState' => ['semanticStatus' => 'continue'],
    ],
]);
assert($match['status'] === 'LIVE_SHADOW_PARITY_MATCH');
assert($match['normalizedTask']['task_id'] === 'loop-live-1');
assert($match['actual']['iteration'] === 1);

$divergence = $evaluator->evaluate([
    'task' => [
        'task_id' => 'loop-live-2',
        'status' => 'blocked',
        'decision_status' => 'done',
        'cycle_checkpoint_stop_reason' => 'completion_candidate',
        'auto_iteration_count' => 2,
        'max_auto_iterations' => 3,
    ],
    'completion_verified' => false,
], ['stopReason' => 'decision_done_verified:done']);
assert($divergence['status'] === 'LIVE_SHADOW_PARITY_DIVERGENCE');
assert(isset($divergence['differences']['stopReason']));

fwrite(STDOUT, "OK: M4 live shadow parity evaluator regression passed.\n");
