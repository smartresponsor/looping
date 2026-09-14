<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopShadowAcceptanceProjector
{
    public function project(array $snapshot): array
    {
        $interactionCount = max(0, (int) ($snapshot['interactionCount'] ?? $snapshot['auto_iteration_count'] ?? 0));
        $maxInteractions = max(1, (int) ($snapshot['maxInteractions'] ?? $snapshot['max_auto_iterations'] ?? 1));
        $submittedCount = max(0, (int) ($snapshot['submittedCount'] ?? 0));
        $capturedCount = max(0, (int) ($snapshot['assistantCapturedCount'] ?? 0));
        $stopReason = $this->stringOrNull($snapshot['stopReason'] ?? $snapshot['stop_reason'] ?? null);
        $completionVerified = ($snapshot['completionVerified'] ?? $snapshot['completion_verified'] ?? false) === true;
        $repositoryVerified = ($snapshot['repositoryVerified'] ?? $snapshot['repository_verified'] ?? false) === true;
        $transportComplete = $interactionCount === $maxInteractions
            && $submittedCount === $maxInteractions
            && $capturedCount === $maxInteractions;
        $verifiedDoneReason = $stopReason !== null && str_starts_with($stopReason, 'decision_done_verified:');
        $taskComplete = $completionVerified && $repositoryVerified && $verifiedDoneReason;

        return [
            'ok' => true,
            'status' => 'SHADOW_ACCEPTANCE_PROJECTED',
            'authoritative' => false,
            'transportAcceptance' => [
                'complete' => $transportComplete,
                'interactionCount' => $interactionCount,
                'maxInteractions' => $maxInteractions,
                'submittedCount' => $submittedCount,
                'assistantCapturedCount' => $capturedCount,
            ],
            'taskAcceptance' => [
                'complete' => $taskComplete,
                'completionVerified' => $completionVerified,
                'repositoryVerified' => $repositoryVerified,
                'stopReason' => $stopReason,
                'budgetExhaustionIsCompletion' => false,
            ],
            'nextAction' => $taskComplete ? 'shadow_accept_verified_completion' : 'shadow_do_not_claim_task_completion',
        ];
    }

    private function stringOrNull(mixed $value): ?string
    {
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
    }
}
