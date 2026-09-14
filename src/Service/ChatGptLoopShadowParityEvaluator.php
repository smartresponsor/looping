<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopShadowParityEvaluator
{
    public function __construct(
        private readonly ChatGptLoopOrchestrationReceiptNormalizer $normalizer,
        private readonly ChatGptLoopShadowStateProjector $stateProjector,
        private readonly ChatGptLoopShadowRecoveryProjector $recoveryProjector,
    ) {
    }

    public function evaluate(array $snapshot, array $authoritative = []): array
    {
        $task = $this->normalizer->normalize($snapshot);
        $normalizedSnapshot = [
            'task' => $task,
            'round' => is_array($snapshot['round'] ?? null) ? $snapshot['round'] : [],
            'completion_verified' => (bool) ($snapshot['completion_verified'] ?? false),
        ];
        $shadow = $this->stateProjector->project($normalizedSnapshot);
        $recovery = $this->recoveryProjector->project($normalizedSnapshot);
        $expected = $this->expected($task, $authoritative);
        $actual = $this->actual($shadow, $recovery);
        $differences = [];

        foreach ($expected as $key => $value) {
            if ($value === null) {
                continue;
            }
            if (($actual[$key] ?? null) !== $value) {
                $differences[$key] = ['authoritative' => $value, 'shadow' => $actual[$key] ?? null];
            }
        }

        $comparedFields = array_keys(array_filter($expected, static fn (mixed $value): bool => $value !== null));
        $decisionEvidenceComplete = is_bool($authoritative['continue'] ?? null)
            && is_bool($authoritative['terminal'] ?? null)
            && ($this->stringPresent($authoritative['decisionStatus'] ?? $authoritative['decision_status'] ?? null)
                || $this->stringPresent($authoritative['stopReason'] ?? $authoritative['stop_reason'] ?? null));
        $status = $differences !== []
            ? 'LIVE_SHADOW_PARITY_DIVERGENCE'
            : ($decisionEvidenceComplete ? 'LIVE_SHADOW_PARITY_MATCH' : 'LIVE_SHADOW_PARITY_MATCH_PARTIAL');

        return [
            'ok' => $differences === [],
            'status' => $status,
            'authoritative' => false,
            'source' => 'live_immutable_receipt_copy',
            'normalizedTask' => $task,
            'shadowState' => $shadow,
            'shadowRecovery' => $recovery,
            'expected' => $expected,
            'actual' => $actual,
            'comparedFields' => $comparedFields,
            'decisionEvidenceComplete' => $decisionEvidenceComplete,
            'differences' => $differences,
        ];
    }

    private function expected(array $task, array $authoritative): array
    {
        return [
            'taskId' => $task['task_id'],
            'chatId' => $task['chat_id'],
            'targetId' => $task['target_id'],
            'taskStatus' => $task['status'],
            'phase' => $task['phase_key'],
            'iteration' => $task['auto_iteration_count'],
            'maxIterations' => $task['max_auto_iterations'],
            'roundIndex' => $task['cycle_round_index'],
            'retryAttempt' => $task['retry_attempt'],
            'progressFingerprint' => $task['cycle_progress_fingerprint'],
            'repeatCount' => $task['cycle_progress_repeat_count'],
            'decisionStatus' => $authoritative['decisionStatus'] ?? $authoritative['decision_status'] ?? null,
            'continue' => is_bool($authoritative['continue'] ?? null) ? $authoritative['continue'] : null,
            'terminal' => is_bool($authoritative['terminal'] ?? null) ? $authoritative['terminal'] : null,
            'stopReason' => $authoritative['stopReason'] ?? $authoritative['stop_reason'] ?? null,
            'nextAction' => $authoritative['nextAction'] ?? $authoritative['next_action'] ?? null,
            'recoveryClass' => $authoritative['recoveryClass'] ?? $authoritative['recovery_class'] ?? null,
        ];
    }

    private function actual(array $shadow, array $recovery): array
    {
        return [
            'taskId' => $shadow['identity']['taskId'] ?? null,
            'chatId' => $shadow['identity']['chatId'] ?? null,
            'targetId' => $shadow['identity']['targetId'] ?? null,
            'taskStatus' => $shadow['lifecycle']['taskStatus'] ?? null,
            'phase' => $shadow['lifecycle']['phase'] ?? null,
            'iteration' => $shadow['lifecycle']['iteration'] ?? null,
            'maxIterations' => $shadow['lifecycle']['maxIterations'] ?? null,
            'roundIndex' => $shadow['lifecycle']['roundIndex'] ?? null,
            'retryAttempt' => $shadow['lifecycle']['retryAttempt'] ?? null,
            'progressFingerprint' => $shadow['checkpoint']['progressFingerprint'] ?? null,
            'repeatCount' => $shadow['checkpoint']['repeatCount'] ?? null,
            'decisionStatus' => $shadow['decision']['marker'] ?? null,
            'continue' => $shadow['decision']['continue'] ?? null,
            'terminal' => $shadow['decision']['terminal'] ?? null,
            'stopReason' => $shadow['decision']['stopReason'] ?? null,
            'nextAction' => $shadow['decision']['nextAction'] ?? null,
            'recoveryClass' => $recovery['recoveryClass'] ?? null,
        ];
    }

    private function stringPresent(mixed $value): bool
    {
        return is_string($value) && trim($value) !== '';
    }
}
