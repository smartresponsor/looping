<?php

declare(strict_types=1);

use App\Service\ChatGptLoopShadowDecisionProjector;
use App\Service\ChatGptLoopShadowRecoveryProjector;
use App\Service\ChatGptLoopShadowStateProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowDecisionProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowRecoveryProjector.php';
require dirname(__DIR__) . '/src/Service/ChatGptLoopShadowStateProjector.php';

$root = dirname(__DIR__);
$corpus = json_decode(
    file_get_contents($root . '/fixtures/orchestration-replay-corpus.json'),
    true,
    512,
    JSON_THROW_ON_ERROR,
);
$stateProjector = new ChatGptLoopShadowStateProjector(new ChatGptLoopShadowDecisionProjector());
$recoveryProjector = new ChatGptLoopShadowRecoveryProjector();

foreach ($corpus['cases'] as $case) {
    $snapshot = [
        'task' => $case['task'],
        'completion_verified' => $case['completion_verified'] ?? false,
    ];
    $state = $stateProjector->project($snapshot);
    $recovery = $recoveryProjector->project($snapshot);
    assert($state['authoritative'] === false);
    assert($recovery['authoritative'] === false);

    if (array_key_exists('stopReason', $case['expected'])) {
        assert(
            $state['decision']['stopReason'] === $case['expected']['stopReason'],
            $case['name'] . ': stop reason mismatch',
        );
    }
    if (array_key_exists('recoveryClass', $case['expected'])) {
        assert(
            $recovery['recoveryClass'] === $case['expected']['recoveryClass'],
            $case['name'] . ': recovery class mismatch',
        );
    }
}

assert(count($corpus['cases']) >= 6);
fwrite(STDOUT, "OK: M3 orchestration replay corpus passed.\n");
