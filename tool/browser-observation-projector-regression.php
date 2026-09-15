<?php

declare(strict_types=1);

use App\Service\ChatGptLoopBrowserObservationProjector;

require dirname(__DIR__) . '/src/Service/ChatGptLoopBrowserObservationProjector.php';

$projector = new ChatGptLoopBrowserObservationProjector();

$ready = $projector->project(
    ['status' => 'LIKELY_STABLE', 'decision' => ['next_action' => 'RUN_STABLE_CAPTURE']],
    ['status' => 'READY_FOR_STABLE_CAPTURE', 'next_action' => 'RUN_PRE_ASK_CAPTURE'],
);
assert($ready['state'] === 'ready_for_capture');
assert($ready['readyForCapture'] === true);

$wait = $projector->project(
    ['status' => 'STREAMING_NO_RECENT_PROGRESS', 'decision' => ['next_action' => 'WAIT_AND_PROBE', 'next_probe_after_ms' => 9000]],
    ['status' => 'STREAMING_NO_RECENT_PROGRESS', 'next_action' => 'WAIT_AND_PROBE'],
);
assert($wait['state'] === 'wait');
assert($wait['nextProbeAfterMs'] === 3000);

$stale = $projector->project(
    ['status' => 'LIKELY_STABLE', 'probe' => ['busy' => false, 'composer_stop_control_mode' => 'not_found', 'composer_action_mode' => 'send', 'messages' => [], 'latest_assistant' => null]],
    ['status' => 'STREAMING_NO_RECENT_PROGRESS'],
);
assert($stale['state'] === 'stale_or_empty_binding');
assert($stale['quietEmptyBinding'] === true);

fwrite(STDOUT, "OK: browser observation projector regression passed.\n");
