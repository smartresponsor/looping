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
        $ports = is_array($state['ports'] ?? null) ? $state['ports'] : [9222, 9223];
        $timeoutMs = max(250, min(10000, (int) ($state['timeoutMs'] ?? 3000)));

        $plan = match ($stage) {
            'chat_bind' => $this->contract('console.write.browser.session.open', [
                'ports' => $ports,
                'url' => $this->string($state['url'] ?? null) ?? 'https://chatgpt.com/',
                'activate' => true,
                'confirmOpen' => true,
                'timeoutMs' => $timeoutMs,
            ], 'write'),
            'composer_preflight' => $targetId === null ? null : $this->contract(
                'console.read_.browser.chatgpt.composer.preflight',
                ['ports' => $ports, 'expectedTargetId' => $targetId, 'timeoutMs' => $timeoutMs],
                'read',
            ),
            'prompt_draft' => $targetId === null || $this->string($state['draftText'] ?? null) === null ? null : $this->contract(
                'console.write.browser.session.input.draft',
                ['ports' => $ports, 'expectedTargetId' => $targetId, 'draftText' => $this->string($state['draftText']), 'allowOverwrite' => ($state['allowOverwrite'] ?? false) === true, 'confirmDraft' => true, 'timeoutMs' => $timeoutMs],
                'write',
            ),
            'prompt_submit' => $targetId === null ? null : $this->contract(
                'console.write.browser.session.submit',
                array_filter(['ports' => $ports, 'expectedTargetId' => $targetId, 'expectedDraftHash' => $this->string($state['draftHash'] ?? null), 'expectedDraftLength' => is_numeric($state['draftLength'] ?? null) ? (int) $state['draftLength'] : null, 'confirmSubmit' => true, 'timeoutMs' => $timeoutMs], static fn (mixed $value): bool => $value !== null),
                'write',
            ),
            'answer_watch' => $this->capture('console.read_.browser.chatgpt.watch.probe', $taskId, $chatId, $targetId, $ports, $timeoutMs, $state),
            'answer_settle' => $this->capture('console.read_.browser.chatgpt.answer.settle', $taskId, $chatId, $targetId, $ports, $timeoutMs, $state),
            'message_capture' => $this->capture('console.read_.browser.chatgpt.message.capture', $taskId, $chatId, $targetId, $ports, $timeoutMs, $state),
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
        if ($tool === 'console.read_.browser.chatgpt.watch.probe') {
            $arguments['phase'] = 'reply_watch';
            $arguments['taskClass'] = $state['taskClass'] ?? 'repo_rc_implementation';
        }
        if ($tool === 'console.read_.browser.chatgpt.answer.settle') {
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
