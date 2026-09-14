<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopShadowRecoveryProjector
{
    public function project(array $snapshot): array
    {
        $task = is_array($snapshot['task'] ?? null) ? $snapshot['task'] : $snapshot;
        $receipt = is_array($task['execution_blocked_receipt'] ?? null) ? $task['execution_blocked_receipt'] : [];
        $status = $this->stringOrNull($task['status'] ?? null);
        $stage = $this->stringOrNull($task['execution_blocked_stage'] ?? null);
        $reason = $this->stringOrNull($task['execution_blocked_reason'] ?? null);
        $retryable = ($receipt['retryable'] ?? false) === true || ($receipt['readiness_retryable'] ?? false) === true;
        $rateLimit = ($receipt['rate_limit_detected'] ?? false) === true || $this->stringOrNull($task['rate_limit_cooldown_until'] ?? null) !== null;
        $orphaned = $reason === 'ENGINE_CYCLE_ANSWER_ORPHANED' || $this->stringOrNull($receipt['inner_status'] ?? null) === 'ENGINE_CYCLE_ANSWER_ORPHANED';
        [$class, $nextAction] = $this->resolve($status, $stage, $reason, $retryable, $rateLimit, $orphaned, $task);

        return [
            'ok' => true,
            'status' => 'SHADOW_RECOVERY_PROJECTED',
            'authoritative' => false,
            'recoveryClass' => $class,
            'nextAction' => $nextAction,
            'retryable' => $retryable,
            'rateLimitDetected' => $rateLimit,
            'orphanedAnswer' => $orphaned,
        ];
    }

    private function resolve(?string $status, ?string $stage, ?string $reason, bool $retryable, bool $rateLimit, bool $orphaned, array $task): array
    {
        if ($rateLimit) {
            return ['wait_rate_limit_cooldown', 'wait_for_cooldown_then_resume_same_task'];
        }
        if ($orphaned) {
            return ['resubmit_orphaned_answer', 'reverify_orphan_then_resubmit_same_prompt'];
        }
        if ($status === 'waiting_runtime') {
            return ['wait_runtime', 'wait_for_runtime_then_resume'];
        }
        if ($status === 'waiting_user') {
            return ['human_decision', 'return_decision_packet_to_user'];
        }
        if ($status === 'blocked') {
            if ($stage === 'chat_bind' && $retryable) {
                return ['rebind_chat', 'rebind_chat_target_then_recheck'];
            }
            if ($stage === 'chat_bind') {
                return ['inspect_chat_surface', 'inspect_chat_surface_without_automatic_mutation'];
            }
            if ($stage === 'answer_capture' && $retryable) {
                return ['retry_answer_capture', 'retry_stable_answer_capture'];
            }
            return ['inspect_blocked_stage', 'inspect_blocked_stage_before_any_retry'];
        }
        if ($status === 'executing' && $this->stringOrNull($task['target_id'] ?? null) !== null) {
            return ['resume_bound_task', 'resume_from_bound_target_checkpoint'];
        }
        if ($status === 'done' || $status === 'completed') {
            return ['none', 'no_recovery_required'];
        }
        if ($reason !== null) {
            return ['inspect_reason', 'inspect_recorded_reason_before_resume'];
        }

        return ['none', 'no_recovery_decision'];
    }

    private function stringOrNull(mixed $value): ?string
    {
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
    }
}
