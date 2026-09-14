<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopOrchestrationReceiptNormalizer
{
    public function normalize(array $snapshot): array
    {
        $task = is_array($snapshot['task'] ?? null) ? $snapshot['task'] : $snapshot;
        $round = is_array($snapshot['round'] ?? null) ? $snapshot['round'] : [];

        return [
            'task_id' => $this->firstString($task['task_id'] ?? null, $task['taskId'] ?? null, $snapshot['task_id'] ?? null),
            'component' => $this->firstString($task['component'] ?? null, $task['name'] ?? null),
            'workspace_path' => $this->firstString($task['workspace_path'] ?? null, $task['workspacePath'] ?? null),
            'chat_id' => $this->firstString($task['chat_id'] ?? null, $task['chatId'] ?? null),
            'target_id' => $this->firstString($task['target_id'] ?? null, $task['targetId'] ?? null),
            'status' => $this->firstString($task['status'] ?? null),
            'phase_key' => $this->firstString($task['phase_key'] ?? null, $task['phase'] ?? null),
            'decision_status' => $this->firstString(
                $task['decision_status'] ?? null,
                $round['decision_status'] ?? null,
                $snapshot['decision_status'] ?? null,
            ),
            'semantic_status' => $this->firstString(
                is_array($task['decisionState'] ?? null) ? ($task['decisionState']['semanticStatus'] ?? null) : null,
                $task['semanticStatus'] ?? null,
                $snapshot['semantic_status'] ?? null,
            ),
            'cycle_checkpoint_stop_reason' => $this->firstString(
                $task['cycle_checkpoint_stop_reason'] ?? null,
                $snapshot['round_stop_reason'] ?? null,
            ),
            'cycle_progress_fingerprint' => $this->firstString(
                $task['cycle_progress_fingerprint'] ?? null,
                $round['progress_fingerprint'] ?? null,
            ),
            'baseline_assistant_hash' => $this->firstString($task['baseline_assistant_hash'] ?? null, $task['currentCycleBaselineAssistantHash'] ?? null),
            'last_assistant_hash' => $this->firstString($task['last_assistant_hash'] ?? null, $task['lastAssistantHash'] ?? null),
            'auto_iteration_count' => $this->firstInt($task['auto_iteration_count'] ?? null, $task['interactionCount'] ?? null, 0),
            'max_auto_iterations' => max(1, $this->firstInt($task['max_auto_iterations'] ?? null, $task['maxInteractions'] ?? null, 5)),
            'cycle_round_index' => $this->firstInt($task['cycle_round_index'] ?? null, $round['round_index'] ?? null, $task['interactionCount'] ?? null, 0),
            'cycle_progress_repeat_count' => max(0, $this->firstInt($task['cycle_progress_repeat_count'] ?? null, $round['repeated_progress_fingerprint_count'] ?? null, 0)),
            'retry_attempt' => max(0, $this->firstInt($task['retry_attempt'] ?? null, $task['attempt'] ?? null, 0)),
            'execution_blocked_stage' => $this->firstString($task['execution_blocked_stage'] ?? null),
            'execution_blocked_reason' => $this->firstString($task['execution_blocked_reason'] ?? null),
            'execution_blocked_receipt' => is_array($task['execution_blocked_receipt'] ?? null) ? $task['execution_blocked_receipt'] : [],
            'rate_limit_cooldown_until' => $this->firstString($task['rate_limit_cooldown_until'] ?? null),
        ];
    }

    private function firstString(mixed ...$values): ?string
    {
        foreach ($values as $value) {
            if (is_string($value) && trim($value) !== '') {
                return trim($value);
            }
        }

        return null;
    }

    private function firstInt(mixed ...$values): int
    {
        foreach ($values as $value) {
            if (is_int($value)) {
                return $value;
            }
            if (is_numeric($value)) {
                return (int) $value;
            }
        }

        return 0;
    }
}
