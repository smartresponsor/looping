<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopShadowDecisionProjector
{
    // Shadow-only: this service projects orchestration decisions and never performs runtime mutations.
    private const CONTINUING = [
        'continue',
        'next',
        'go',
        'do it',
        'commit',
        'commit and continue',
        'commit and next',
        'fix fail and continue',
        'fix fail and go',
        'fix fail and next',
        'fix fail and commit',
        'fix fail, commit and continue',
        'fix blocker and continue',
        'recheck and continue',
    ];

    public function project(array $snapshot): array
    {
        $marker = $this->normalizeMarker($snapshot['decision_status'] ?? null);
        $roundStopReason = (string) ($snapshot['round_stop_reason'] ?? 'complete');
        $repeatCount = (int) ($snapshot['repeated_progress_fingerprint_count'] ?? 0);
        $iteration = (int) ($snapshot['auto_iteration_count'] ?? 0);
        $maxIterations = max(1, (int) ($snapshot['max_auto_iterations'] ?? 5));

        $stopReason = $this->resolveStopReason(
            $marker,
            $roundStopReason,
            $repeatCount,
            $iteration,
            $maxIterations,
            (bool) ($snapshot['completion_verified'] ?? false),
        );

        return [
            'ok' => true,
            'status' => 'SHADOW_ORCHESTRATION_DECISION_PROJECTED',
            'authoritative' => false,
            'marker' => $marker,
            'stopReason' => $stopReason,
            'continue' => $stopReason === null,
            'terminal' => $stopReason !== null,
            'nextAction' => $stopReason === null ? 'shadow_continue_next_round' : 'shadow_stop_without_runtime_mutation',
        ];
    }

    private function resolveStopReason(
        ?string $marker,
        string $roundStopReason,
        int $repeatCount,
        int $iteration,
        int $maxIterations,
        bool $completionVerified,
    ): ?string {
        if ($roundStopReason === 'human_decision_required' || $marker === 'human decision required') {
            return 'human_decision_required';
        }

        if ($roundStopReason === 'completion_candidate' || $marker === 'done') {
            return $completionVerified ? 'decision_done_verified:done' : 'completion_verification_required';
        }

        if ($roundStopReason !== 'complete') {
            return $roundStopReason;
        }

        if ($repeatCount >= 3) {
            return 'stalled_no_semantic_progress';
        }

        if (!$this->isContinuing($marker)) {
            return 'decision_recheck_required:' . ($marker ?? 'unknown');
        }

        if ($iteration >= $maxIterations) {
            return 'max_rounds';
        }

        return null;
    }

    private function isContinuing(?string $marker): bool
    {
        return $marker !== null && in_array($marker, self::CONTINUING, true);
    }


    private function normalizeMarker(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }

        $normalized = preg_replace('/\s+/', ' ', str_replace(['_', '.', '-'], ' ', strtolower(trim($value))));
        if (!is_string($normalized) || $normalized === '') {
            return null;
        }

        return match ($normalized) {
            'green', 'allow', 'correct and continue', 'attention', 'go next' => 'continue',
            'do fix', 'red' => 'fix fail and continue',
            'recheck', 'wait', 'retry' => 'recheck and continue',
            'complete', 'completed', 'task done' => 'done',
            default => $normalized,
        };
    }
}
