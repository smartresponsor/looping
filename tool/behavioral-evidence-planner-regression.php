<?php
declare(strict_types=1);
use App\Service\ChatGptLoopBehavioralEvidencePlanner;
require dirname(__DIR__) . '/src/Service/ChatGptLoopBehavioralEvidencePlanner.php';

$planner = new ChatGptLoopBehavioralEvidencePlanner();

$none = $planner->applicability(['docs/readme.md'], []);
assert($none['required'] === false);
assert($none['surface'] === 'none');

$web = $planner->applicability(['templates/home.html.twig', 'src/Service/Foo.php'], ['npm:test:ui']);
assert($web['required'] === true);
assert($web['surface'] === 'web_ui');
assert($web['expectedPlatforms'] === ['web']);

$blocked = $planner->evaluate(
    $web,
    ['required' => true, 'ok' => false],
    ['schema' => 'bad', 'producer' => 'unknown', 'platform' => 'android', 'captured_at' => '2026-09-14T20:00:00Z'],
    '2026-09-14T21:00:00Z',
);
assert($blocked['verified'] === false);
assert(in_array('reuse_first_runtime_not_ready', $blocked['blockers'], true));
assert(in_array('visual_artifact_schema_invalid', $blocked['blockers'], true));
assert(in_array('visual_artifact_producer_unverified', $blocked['blockers'], true));
assert(in_array('visual_artifact_not_fresh_for_task', $blocked['blockers'], true));
assert(in_array('visual_artifact_platform_mismatch', $blocked['blockers'], true));

$verified = $planner->evaluate(
    $web,
    ['required' => true, 'ok' => true],
    ['schema' => 'visual-artifact-run-v1', 'producer' => 'playwright', 'platform' => 'web', 'captured_at' => '2026-09-14T22:00:00Z'],
    '2026-09-14T21:00:00Z',
);
assert($verified['verified'] === true);
assert($verified['blockers'] === []);

fwrite(STDOUT, "OK: behavioral evidence planner regression passed.\n");
