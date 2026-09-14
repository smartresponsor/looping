<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowDecisionProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';

$projector = new ChatGptLoopShadowDecisionProjector();

$cases = [
    [['decision_status' => 'continue', 'round_stop_reason' => 'complete', 'repeated_progress_fingerprint_count' => 1, 'auto_iteration_count' => 2, 'max_auto_iterations' => 5], null, true],
    [['decision_status' => 'done', 'round_stop_reason' => 'completion_candidate', 'completion_verified' => false], 'completion_verification_required', false],
    [['decision_status' => 'done', 'round_stop_reason' => 'completion_candidate', 'completion_verified' => true], 'decision_done_verified:done', false],
    [['decision_status' => 'human decision required', 'round_stop_reason' => 'complete'], 'human_decision_required', false],
    [['decision_status' => 'continue', 'round_stop_reason' => 'complete', 'repeated_progress_fingerprint_count' => 3], 'stalled_no_semantic_progress', false],
    [['decision_status' => 'continue', 'round_stop_reason' => 'complete', 'auto_iteration_count' => 5, 'max_auto_iterations' => 5], 'max_rounds', false],
    [['decision_status' => 'unknown state', 'round_stop_reason' => 'complete'], 'decision_recheck_required:unknown state', false],
];

foreach ($cases as [$input, $expectedStopReason, $expectedContinue]) {
    $result = $projector->project($input);
    assert($result['authoritative'] === false);
    assert($result['stopReason'] === $expectedStopReason);
    assert($result['continue'] === $expectedContinue);
}

fwrite(STDOUT, "OK: shadow orchestration decision projector regression passed.\n");
