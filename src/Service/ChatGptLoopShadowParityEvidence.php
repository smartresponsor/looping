<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopShadowParityEvidence
{
    private const REQUIRED_COVERAGE = ['continue', 'blocked', 'retry', 'rate_limit', 'orphan', 'human_decision', 'stall', 'completion'];

    public function summarize(array $artifacts): array
    {
        $counts = ['match' => 0, 'partial' => 0, 'divergence' => 0, 'unknown' => 0];
        $divergences = [];
        $coverage = [];
        $completeCoverage = [];
        $provenanceRejected = [];

        foreach ($artifacts as $artifact) {
            if (!is_array($artifact)) {
                $counts['unknown']++;
                continue;
            }
            $classes = $this->classifyCoverage($artifact);
            foreach ($classes as $class) {
                $coverage[$class] = true;
            }
            $status = (string) ($artifact['status'] ?? '');
            $provenanceEligible = $this->hasEligibleProvenance($artifact);
            if ($status === 'LIVE_SHADOW_PARITY_MATCH') {
                $counts['match']++;
                if ($provenanceEligible) {
                    foreach ($classes as $class) {
                        $completeCoverage[$class] = true;
                    }
                } elseif ($classes !== []) {
                    $provenanceRejected[] = $this->provenanceRejection($artifact, $classes);
                }
                continue;
            }
            if ($status === 'LIVE_SHADOW_PARITY_MATCH_PARTIAL') {
                $counts['partial']++;
                continue;
            }
            if ($status === 'LIVE_SHADOW_PARITY_DIVERGENCE') {
                $differences = is_array($artifact['differences'] ?? null) ? $artifact['differences'] : [];
                if ($this->isRepresentationOnlyDecisionStatusDifference($differences)) {
                    $counts['match']++;
                    if ($provenanceEligible) {
                        foreach ($classes as $class) {
                            $completeCoverage[$class] = true;
                        }
                    } elseif ($classes !== []) {
                        $provenanceRejected[] = $this->provenanceRejection($artifact, $classes);
                    }
                    continue;
                }
                $counts['divergence']++;
                $divergences[] = [
                    'capturedAt' => $artifact['capturedAt'] ?? null,
                    'taskId' => $artifact['normalizedTask']['task_id'] ?? null,
                    'differences' => $differences,
                ];
                continue;
            }
            $counts['unknown']++;
        }

        $total = array_sum($counts);
        $complete = $counts['match'] + $counts['divergence'];
        $zeroDivergence = $counts['divergence'] === 0;
        $observedCoverage = array_keys($coverage);
        sort($observedCoverage, SORT_STRING);
        $completeCoverageClasses = array_keys($completeCoverage);
        sort($completeCoverageClasses, SORT_STRING);
        $missingCoverage = array_values(array_diff(self::REQUIRED_COVERAGE, $observedCoverage));
        $missingCompleteCoverage = array_values(array_diff(self::REQUIRED_COVERAGE, $completeCoverageClasses));
        $ready = $total > 0 && $complete > 0 && $zeroDivergence && $missingCompleteCoverage === [];

        return [
            'ok' => $zeroDivergence,
            'status' => $counts['divergence'] > 0
                ? 'M4_SHADOW_PARITY_EVIDENCE_DIVERGENCE'
                : ($ready ? 'M4_SHADOW_PARITY_EVIDENCE_READY' : 'M4_SHADOW_PARITY_EVIDENCE_INCOMPLETE'),
            'authoritative' => false,
            'runtimeEffect' => 'none',
            'artifactCount' => $total,
            'completeComparisonCount' => $complete,
            'counts' => $counts,
            'zeroUnexplainedDivergence' => $zeroDivergence,
            'm4EvidenceReady' => $ready,
            'requiredCoverage' => self::REQUIRED_COVERAGE,
            'observedCoverage' => $observedCoverage,
            'completeCoverage' => $completeCoverageClasses,
            'missingCoverage' => $missingCoverage,
            'missingCompleteCoverage' => $missingCompleteCoverage,
            'divergences' => $divergences,
            'provenanceRejected' => $provenanceRejected,
        ];
    }

    private function hasEligibleProvenance(array $artifact): bool
    {
        $provenance = is_array($artifact['provenance'] ?? null) ? $artifact['provenance'] : [];
        if (($provenance['immutableReceipt'] ?? false) !== true) {
            return false;
        }
        $origin = $provenance['origin'] ?? null;
        $taskId = $provenance['sourceTaskId'] ?? null;
        if (!is_string($taskId) || trim($taskId) === '') {
            return false;
        }
        if ($origin === 'live_task_bank') {
            return is_string($artifact['capturedAt'] ?? null) && trim($artifact['capturedAt']) !== '';
        }
        if ($origin === 'console_engine_history') {
            return is_string($provenance['sourceEventId'] ?? null)
                && trim($provenance['sourceEventId']) !== ''
                && is_string($provenance['sourceEventTs'] ?? null)
                && trim($provenance['sourceEventTs']) !== '';
        }
        return false;
    }

    private function provenanceRejection(array $artifact, array $classes): array
    {
        return [
            'taskId' => $artifact['normalizedTask']['task_id'] ?? ($artifact['provenance']['sourceTaskId'] ?? null),
            'classes' => $classes,
            'origin' => $artifact['provenance']['origin'] ?? null,
            'reason' => 'm4_complete_coverage_requires_immutable_live_or_console_history_provenance',
        ];
    }

    private function isRepresentationOnlyDecisionStatusDifference(array $differences): bool
    {
        if (array_keys($differences) !== ['decisionStatus']) {
            return false;
        }
        $difference = $differences['decisionStatus'];
        if (!is_array($difference)) {
            return false;
        }

        return $this->canonical($difference['authoritative'] ?? null) === $this->canonical($difference['shadow'] ?? null);
    }

    private function canonical(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $normalized = preg_replace('/\s+/', ' ', str_replace(['_', '.', '-'], ' ', strtolower(trim($value))));
        return is_string($normalized) && $normalized !== '' ? $normalized : null;
    }

    private function classifyCoverage(array $artifact): array
    {
        $explicit = $artifact['coverageClass'] ?? $artifact['coverage_class'] ?? null;
        if (is_string($explicit) && in_array($explicit, self::REQUIRED_COVERAGE, true)) {
            return [$explicit];
        }

        $task = is_array($artifact['normalizedTask'] ?? null) ? $artifact['normalizedTask'] : [];
        $recovery = is_array($artifact['shadowRecovery'] ?? null) ? $artifact['shadowRecovery'] : [];
        $shadowState = is_array($artifact['shadowState'] ?? null) ? $artifact['shadowState'] : [];
        $decision = is_array($shadowState['decision'] ?? null) ? $shadowState['decision'] : [];
        $actual = is_array($artifact['actual'] ?? null) ? $artifact['actual'] : [];
        $classes = [];

        $recoveryClass = $recovery['recoveryClass'] ?? $actual['recoveryClass'] ?? null;
        if (in_array($recoveryClass, ['rate_limit', 'wait_rate_limit_cooldown'], true)) $classes[] = 'rate_limit';
        if (in_array($recoveryClass, ['orphaned_answer', 'resubmit_orphaned_answer'], true)) $classes[] = 'orphan';
        if (in_array($recoveryClass, ['retryable_blocked', 'runtime_wait', 'rebind_chat', 'retry_answer_capture', 'resume_bound_task', 'wait_runtime'], true)) $classes[] = 'retry';
        if ($recoveryClass === 'rebind_chat') $classes[] = 'blocked';

        $status = (string) ($task['status'] ?? '');
        if ($status === 'blocked' || is_string($task['execution_blocked_stage'] ?? null)) $classes[] = 'blocked';

        $decisionStatus = $this->canonical($task['decision_status'] ?? $decision['marker'] ?? null);
        $stopReason = $this->canonical($actual['stopReason'] ?? $decision['stopReason'] ?? $task['cycle_checkpoint_stop_reason'] ?? null);
        if ($decisionStatus === 'human decision required' || $stopReason === 'human decision required') $classes[] = 'human_decision';
        if ($stopReason === 'stalled no semantic progress') $classes[] = 'stall';
        if ($decisionStatus === 'done' || (is_string($stopReason) && str_starts_with($stopReason, 'decision done verified'))) $classes[] = 'completion';

        $continue = $actual['continue'] ?? $decision['continue'] ?? null;
        if ($continue === true || in_array($decisionStatus, ['continue', 'next', 'go', 'recheck and continue'], true)) {
            $classes[] = 'continue';
        }

        return array_values(array_unique(array_filter(
            $classes,
            static fn (string $class): bool => in_array($class, self::REQUIRED_COVERAGE, true),
        )));
    }
}
