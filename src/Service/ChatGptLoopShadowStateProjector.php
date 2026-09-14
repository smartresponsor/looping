<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopShadowStateProjector
{
    public function __construct(private readonly ChatGptLoopShadowDecisionProjector $decisionProjector)
    {
    }

    public function project(array $snapshot): array
    {
        $task = is_array($snapshot['task'] ?? null) ? $snapshot['task'] : [];
        $round = is_array($snapshot['round'] ?? null) ? $snapshot['round'] : [];
        $decision = $this->decisionProjector->project([
            'decision_status' => $task['decision_status'] ?? $round['decision_status'] ?? null,
            'round_stop_reason' => $round['round_stop_reason'] ?? 'complete',
            'repeated_progress_fingerprint_count' => $round['repeated_progress_fingerprint_count'] ?? $task['cycle_progress_repeat_count'] ?? 0,
            'auto_iteration_count' => $task['auto_iteration_count'] ?? 0,
            'max_auto_iterations' => $task['max_auto_iterations'] ?? 5,
            'completion_verified' => (bool) ($snapshot['completion_verified'] ?? false),
        ]);
        $iteration = max(0, (int) ($task['auto_iteration_count'] ?? 0));
        $maxIterations = max(1, (int) ($task['max_auto_iterations'] ?? 5));

        return [
            'ok' => true,
            'status' => 'SHADOW_ORCHESTRATION_STATE_PROJECTED',
            'authoritative' => false,
            'source' => 'captured_console_receipt',
            'identity' => [
                'taskId' => $this->stringOrNull($task['task_id'] ?? $snapshot['task_id'] ?? null),
                'component' => $this->stringOrNull($task['component'] ?? null),
                'workspacePath' => $this->stringOrNull($task['workspace_path'] ?? null),
                'chatId' => $this->stringOrNull($task['chat_id'] ?? null),
                'targetId' => $this->stringOrNull($task['target_id'] ?? null),
            ],
            'lifecycle' => [
                'taskStatus' => $this->stringOrNull($task['status'] ?? null),
                'phase' => $this->stringOrNull($task['phase_key'] ?? null),
                'roundIndex' => max(0, (int) ($task['cycle_round_index'] ?? $round['round_index'] ?? 0)),
                'iteration' => $iteration,
                'maxIterations' => $maxIterations,
                'remainingIterations' => max(0, $maxIterations - $iteration),
                'retryAttempt' => max(0, (int) ($task['retry_attempt'] ?? $task['rate_limit_attempt'] ?? 0)),
            ],
            'checkpoint' => [
                'progressFingerprint' => $this->stringOrNull($round['progress_fingerprint'] ?? $task['cycle_progress_fingerprint'] ?? null),
                'repeatCount' => max(0, (int) ($round['repeated_progress_fingerprint_count'] ?? $task['cycle_progress_repeat_count'] ?? 0)),
                'baselineAssistantHash' => $this->stringOrNull($task['baseline_assistant_hash'] ?? null),
                'lastAssistantHash' => $this->stringOrNull($task['last_assistant_hash'] ?? null),
            ],
            'decision' => $decision,
            'nextAction' => $decision['nextAction'],
        ];
    }

    public function compare(array $authoritative, array $shadow): array
    {
        $expected = [
            'taskId' => $this->stringOrNull($authoritative['task_id'] ?? null),
            'chatId' => $this->stringOrNull($authoritative['chat_id'] ?? null),
            'targetId' => $this->stringOrNull($authoritative['target_id'] ?? null),
            'iteration' => max(0, (int) ($authoritative['auto_iteration_count'] ?? 0)),
            'maxIterations' => max(1, (int) ($authoritative['max_auto_iterations'] ?? 5)),
            'decisionStatus' => $this->stringOrNull($authoritative['decision_status'] ?? null),
        ];
        $actual = [
            'taskId' => $shadow['identity']['taskId'] ?? null,
            'chatId' => $shadow['identity']['chatId'] ?? null,
            'targetId' => $shadow['identity']['targetId'] ?? null,
            'iteration' => $shadow['lifecycle']['iteration'] ?? null,
            'maxIterations' => $shadow['lifecycle']['maxIterations'] ?? null,
            'decisionStatus' => $shadow['decision']['marker'] ?? null,
        ];
        $differences = [];
        foreach ($expected as $key => $value) {
            if ($actual[$key] !== $value) {
                $differences[$key] = ['authoritative' => $value, 'shadow' => $actual[$key]];
            }
        }

        return [
            'ok' => $differences === [],
            'status' => $differences === [] ? 'SHADOW_STATE_PARITY_MATCH' : 'SHADOW_STATE_PARITY_DIVERGENCE',
            'authoritative' => false,
            'differences' => $differences,
            'expected' => $expected,
            'actual' => $actual,
        ];
    }

    private function stringOrNull(mixed $value): ?string
    {
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
    }
}
