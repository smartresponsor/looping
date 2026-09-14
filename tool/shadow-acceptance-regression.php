<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowAcceptanceProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowAcceptanceProjector.php';

$projector = new ChatGptLoopShadowAcceptanceProjector();

$budget = $projector->project([
    'interactionCount' => 3,
    'maxInteractions' => 3,
    'submittedCount' => 3,
    'assistantCapturedCount' => 3,
    'stopReason' => 'max_rounds',
]);
assert($budget['transportAcceptance']['complete'] === true);
assert($budget['taskAcceptance']['complete'] === false);
assert($budget['taskAcceptance']['budgetExhaustionIsCompletion'] === false);

$done = $projector->project([
    'interactionCount' => 2,
    'maxInteractions' => 5,
    'submittedCount' => 2,
    'assistantCapturedCount' => 2,
    'stopReason' => 'decision_done_verified:done',
    'completionVerified' => true,
    'repositoryVerified' => true,
]);
assert($done['taskAcceptance']['complete'] === true);
assert($done['nextAction'] === 'shadow_accept_verified_completion');

