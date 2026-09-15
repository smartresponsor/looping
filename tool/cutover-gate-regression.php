<?php

declare(strict_types=1);

use App\Service\ChatGptLoopCutoverGate;

require dirname(__DIR__) . '/src/Service/ChatGptLoopCutoverGate.php';

$gate = new ChatGptLoopCutoverGate();
$manifest = ['consoleAuthority' => true, 'chatGptLoopAuthority' => false, 'consoleCleanupAllowed' => false];
$boundary = ['baselineStable' => true, 'newBoundaryViolationCount' => 0, 'migrationComplete' => false];

$blocked = $gate->evaluate($manifest, [
    'm4EvidenceReady' => false,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => ['retry'],
], $boundary, []);
assert($blocked['status'] === 'CUTOVER_NOT_ELIGIBLE');
assert($blocked['m5OptInEligible'] === false);

$m5 = $gate->evaluate($manifest, [
    'm4EvidenceReady' => true,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
], $boundary, []);
assert($m5['status'] === 'M5_OPT_IN_CUTOVER_ELIGIBLE');
assert($m5['m5OptInEligible'] === true);
assert($m5['m6DefaultCutoverEligible'] === false);

$m6 = $gate->evaluate($manifest, [
    'm4EvidenceReady' => true,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
], $boundary, ['m5Accepted' => true, 'accepted' => true]);
assert($m6['status'] === 'M6_DEFAULT_CUTOVER_ELIGIBLE');
assert($m6['m6DefaultCutoverEligible'] === true);

assert($gate->assertManifestSafe($manifest)['ok'] === true);
assert($gate->assertManifestSafe([
    'consoleAuthority' => false,
    'chatGptLoopAuthority' => true,
    'consoleCleanupAllowed' => true,
])['ok'] === false);
