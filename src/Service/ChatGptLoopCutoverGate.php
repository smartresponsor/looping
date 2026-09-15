<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopCutoverGate
{
    public function evaluate(array $manifest, array $m4, array $boundary, array $rollback): array
    {
        $m4Ready = ($m4['m4EvidenceReady'] ?? false) === true
            && ($m4['zeroUnexplainedDivergence'] ?? false) === true
            && ($m4['missingCoverage'] ?? ['unknown']) === [];
        $boundaryStable = ($boundary['baselineStable'] ?? false) === true
            && (int) ($boundary['newBoundaryViolationCount'] ?? 1) === 0;
        $m5Accepted = ($rollback['m5Accepted'] ?? $rollback['m5_accepted'] ?? false) === true;
        $rollbackAccepted = ($rollback['accepted'] ?? false) === true;
        $optInEligible = $m4Ready && $boundaryStable;
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
                'boundaryStable' => $boundaryStable,
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
