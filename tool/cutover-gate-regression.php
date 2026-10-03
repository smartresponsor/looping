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
assert($blocked['checks']['m4MissingCompleteCoverage'] === ['retry']);

$partialObservedButIncomplete = $gate->evaluate($manifest, [
    'm4EvidenceReady' => false,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
    'missingCompleteCoverage' => ['retry'],
], $boundary, []);
assert($partialObservedButIncomplete['status'] === 'CUTOVER_NOT_ELIGIBLE');
assert($partialObservedButIncomplete['checks']['m4MissingCompleteCoverage'] === ['retry']);

$currentTransportBlocked = $gate->evaluate($manifest, [
    'm4EvidenceReady' => true,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
], $boundary, [], ['legacyEntrypointRequired' => true, 'bridgeBlockers' => ['write.browser.session.open']]);
assert($currentTransportBlocked['status'] === 'CUTOVER_NOT_ELIGIBLE');
assert($currentTransportBlocked['checks']['atomicTransportReady'] === false);

$readyTransport = ['legacyEntrypointRequired' => false, 'bridgeBlockers' => []];
$completionBlocked = $gate->evaluate($manifest, [
    'm4EvidenceReady' => true,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
], $boundary, [], $readyTransport, ['readyForM5Execution' => false, 'blockers' => ['atomic_git_diff_check_missing']]);
assert($completionBlocked['status'] === 'CUTOVER_NOT_ELIGIBLE');
assert($completionBlocked['checks']['completionVerificationReady'] === false);

$readyCompletion = ['readyForM5Execution' => true, 'blockers' => []];
$m5 = $gate->evaluate($manifest, [
    'm4EvidenceReady' => true,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
], $boundary, [], $readyTransport, $readyCompletion);
assert($m5['status'] === 'M5_OPT_IN_CUTOVER_ELIGIBLE');
assert($m5['m5OptInEligible'] === true);
assert($m5['m6DefaultCutoverEligible'] === false);

$m6 = $gate->evaluate($manifest, [
    'm4EvidenceReady' => true,
    'zeroUnexplainedDivergence' => true,
    'missingCoverage' => [],
], $boundary, ['m5Accepted' => true, 'accepted' => true], $readyTransport, $readyCompletion);
assert($m6['status'] === 'M6_DEFAULT_CUTOVER_ELIGIBLE');
assert($m6['m6DefaultCutoverEligible'] === true);

assert($gate->assertManifestSafe($manifest)['ok'] === true);
assert($gate->assertManifestSafe([
    'consoleAuthority' => false,
    'chatGptLoopAuthority' => true,
    'consoleCleanupAllowed' => true,
])['ok'] === false);

fwrite(STDOUT, "OK: cutover gate regression passed.\n");
