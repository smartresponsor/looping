<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopM5AtomicDispatchPlanner
{
    public function plan(array $cutoverGate, string $stage, array $state): array
    {
        if (($cutoverGate['m5OptInEligible'] ?? false) !== true) {
            return $this->blocked('M5_ATOMIC_DISPATCH_CUTOVER_GATE_CLOSED');
        }

        $taskId = $this->string($state['taskId'] ?? $state['task_id'] ?? null);
        $targetId = $this->string($state['targetId'] ?? $state['target_id'] ?? null);
        $chatId = $this->string($state['chatId'] ?? $state['chat_id'] ?? null);
        $ports = $state['ports'] ?? null;
        if ($ports !== [9224] || $targetId === null || preg_match('/^[A-Fa-f0-9]{32}$/D', $targetId) !== 1) {
            return $this->blocked('M5_ATOMIC_EXACT_VISIBLE_TARGET_REQUIRED');
        }
        if ($chatId !== null && preg_match('/^[A-Fa-f0-9-]{36}$/D', $chatId) !== 1) {
            return $this->blocked('M5_ATOMIC_CHAT_ID_INVALID');
        }
        if ($stage === 'prompt_submit' && (preg_match('/^[a-f0-9]{64}$/D', (string) ($state['draftHash'] ?? '')) !== 1)) {
            return $this->blocked('M5_ATOMIC_SUBMIT_EVIDENCE_REQUIRED');
        }
        $timeoutMs = max(250, min(10000, (int) ($state['timeoutMs'] ?? 3000)));

        $plan = match ($stage) {
            // Browser creation remains a separately supervised step; binding is read-only.
            'chat_bind' => $this->contract('read_.browser.chatgpt.composer.preflight', [
                'ports' => $ports,
                'expectedTargetId' => $targetId,
                'timeoutMs' => $timeoutMs,
            ], 'read'),
            'composer_preflight' => $targetId === null ? null : $this->contract(
                'read_.browser.chatgpt.composer.preflight',
                ['ports' => $ports, 'expectedTargetId' => $targetId, 'timeoutMs' => $timeoutMs],
                'read',
            ),
            'prompt_draft' => $chatId === null || $this->string($state['draftText'] ?? null) === null ? null : $this->contract(
                'write.browser.session.input.draft',
                ['ports' => $ports, 'expectedTargetId' => $targetId, 'draftText' => $this->string($state['draftText']), 'allowOverwrite' => ($state['allowOverwrite'] ?? false) === true, 'confirmDraft' => true, 'timeoutMs' => $timeoutMs],
                'write',
            ),
            'prompt_submit' => $chatId === null || $this->string($state['draftHash'] ?? null) === null || !is_int($state['draftLength'] ?? null) || $state['draftLength'] < 1 ? null : $this->contract(
                'write.browser.session.submit',
                array_filter(['ports' => $ports, 'expectedTargetId' => $targetId, 'expectedDraftHash' => $this->string($state['draftHash'] ?? null), 'expectedDraftLength' => is_numeric($state['draftLength'] ?? null) ? (int) $state['draftLength'] : null, 'confirmSubmit' => true, 'timeoutMs' => $timeoutMs], static fn (mixed $value): bool => $value !== null),
                'write',
            ),
            'answer_watch' => $this->capture('read_.browser.chatgpt.watch.probe', $taskId, $chatId, $targetId, $ports, $timeoutMs, $state),
            'answer_settle' => $this->capture('read_.browser.chatgpt.answer.settle', $taskId, $chatId, $targetId, $ports, $timeoutMs, $state),
            'message_capture' => $this->capture('read_.browser.chatgpt.message.capture', $taskId, $chatId, $targetId, $ports, $timeoutMs, $state),
            default => null,
        };

        if ($plan === null) {
            return $this->blocked('M5_ATOMIC_DISPATCH_STATE_INCOMPLETE');
        }

        return ['ok' => true, 'status' => 'M5_ATOMIC_DISPATCH_PLAN_READY', 'authoritative' => false, 'runtimeEffect' => 'none', 'stage' => $stage, 'runnerExecutionPlan' => $plan];
    }

    private function capture(string $tool, ?string $taskId, ?string $chatId, ?string $targetId, array $ports, int $timeoutMs, array $state): ?array
    {
        if ($taskId === null || $targetId === null) return null;

        $arguments = ['ports' => $ports, 'preferredChatId' => $chatId, 'expectedTargetId' => $targetId, 'expectedTaskId' => $taskId, 'requireChatId' => $chatId !== null, 'maxMessages' => max(1, min(100, (int) ($state['maxMessages'] ?? 30))), 'timeoutMs' => $timeoutMs];
        if ($tool === 'read_.browser.chatgpt.watch.probe') {
            $arguments['phase'] = 'reply_watch';
            $arguments['taskClass'] = $state['taskClass'] ?? 'normal_answer';
        }
        if ($tool === 'read_.browser.chatgpt.answer.settle') {
            $arguments['readinessProfile'] = $state['readinessProfile'] ?? 'rc_gate';
            $arguments['requireComposerSendMode'] = true;
            if ($this->string($state['baselineAssistantHash'] ?? null) !== null) $arguments['baselineAssistantHash'] = $this->string($state['baselineAssistantHash']);
        }

        return $this->contract($tool, array_filter($arguments, static fn (mixed $value): bool => $value !== null), 'read');
    }

    private function contract(string $tool, array $arguments, string $mutation): array
    {
        return ['tool' => $tool, 'arguments' => $arguments, 'mutation' => $mutation, 'authorityMode' => 'm5_opt_in'];
    }

    private function blocked(string $status): array
    {
        return ['ok' => false, 'status' => $status, 'authoritative' => false, 'runtimeEffect' => 'none', 'runnerExecutionPlan' => null];
    }

    private function string(mixed $value): ?string
    {
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
    }
}
