<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopCutoverGate
{
    public function evaluate(array $manifest, array $m4, array $boundary, array $rollback, array $transport = [], array $completion = []): array
    {
        $missingCompleteCoverage = $m4['missingCompleteCoverage'] ?? $m4['missingCoverage'] ?? ['unknown'];
        $m4Ready = ($m4['m4EvidenceReady'] ?? false) === true
            && ($m4['zeroUnexplainedDivergence'] ?? false) === true
            && is_array($missingCompleteCoverage)
            && $missingCompleteCoverage === [];
        $boundaryStable = ($boundary['baselineStable'] ?? false) === true
            && (int) ($boundary['newBoundaryViolationCount'] ?? 1) === 0;
        $bridgeBlockers = is_array($transport['bridgeBlockers'] ?? null) ? $transport['bridgeBlockers'] : ['unknown'];
        $atomicTransportReady = ($transport['legacyEntrypointRequired'] ?? true) === false && $bridgeBlockers === [];
        $completionBlockers = is_array($completion['blockers'] ?? null) ? $completion['blockers'] : ['unknown'];
        $completionVerificationReady = ($completion['readyForM5Execution'] ?? false) === true && $completionBlockers === [];
        $m5Accepted = ($rollback['m5Accepted'] ?? $rollback['m5_accepted'] ?? false) === true;
        $rollbackAccepted = ($rollback['accepted'] ?? false) === true;
        $optInEligible = $m4Ready && $boundaryStable && $atomicTransportReady && $completionVerificationReady;
        $defaultEligible = $optInEligible && $m5Accepted && $rollbackAccepted;

        return [
            'ok' => true,
            'status' => $defaultEligible
                ? 'M6_DEFAULT_CUTOVER_ELIGIBLE'
                : ($optInEligible ? 'M5_OPT_IN_CUTOVER_ELIGIBLE' : 'CUTOVER_NOT_ELIGIBLE'),
            'authoritative' => false,
            'runtimeEffect' => 'none',
            'checks' => [
                'consoleAuthorityStillOn' => ($manifest['consoleAuthority'] ?? null) === true,
                'chatGptLoopAuthorityStillOff' => ($manifest['chatGptLoopAuthority'] ?? null) === false,
                'm4EvidenceReady' => $m4Ready,
                'm4MissingCompleteCoverage' => is_array($missingCompleteCoverage) ? $missingCompleteCoverage : ['unknown'],
                'boundaryStable' => $boundaryStable,
                'atomicTransportReady' => $atomicTransportReady,
                'transportBridgeBlockers' => $bridgeBlockers,
                'completionVerificationReady' => $completionVerificationReady,
                'completionBlockers' => $completionBlockers,
                'boundaryMigrationComplete' => ($boundary['migrationComplete'] ?? false) === true,
                'm5Accepted' => $m5Accepted,
                'rollbackAccepted' => $rollbackAccepted,
            ],
            'm5OptInEligible' => $optInEligible,
            'm6DefaultCutoverEligible' => $defaultEligible,
            'nextAction' => $optInEligible
                ? 'enable_only_explicit_opt_in_path_after_separate_authority_change'
                : 'continue_shadow_migration_without_cutover',
        ];
    }

    public function assertManifestSafe(array $manifest): array
    {
        $safe = ($manifest['consoleAuthority'] ?? null) === true
            && ($manifest['chatGptLoopAuthority'] ?? null) === false
            && ($manifest['consoleCleanupAllowed'] ?? null) === false;

        return [
            'ok' => $safe,
            'status' => $safe ? 'SHADOW_MANIFEST_SAFE' : 'SHADOW_MANIFEST_UNSAFE',
            'authoritative' => false,
            'runtimeEffect' => 'none',
        ];
    }
}
