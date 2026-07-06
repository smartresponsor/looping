<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopRunnerExecutionPlan
{
    public function fromEnvelope(?array $dispatchEnvelope): array
    {
        if ($dispatchEnvelope === null) {
            return ['ok' => false, 'status' => 'RUNNER_EXECUTION_NO_ENVELOPE'];
        }

        $tool = (string) ($dispatchEnvelope['tool'] ?? '');
        $mutation = (string) ($dispatchEnvelope['mutation'] ?? 'unknown');
        $confirmationRequired = ($dispatchEnvelope['confirmationRequired'] ?? true) === true;

        if ($tool !== 'console.read_.browser.chatgpt.entrypoint.plan') {
            return ['ok' => false, 'status' => 'RUNNER_EXECUTION_TOOL_NOT_ALLOWED', 'tool' => $tool];
        }

        if ($mutation !== 'none' || $confirmationRequired) {
            return ['ok' => false, 'status' => 'RUNNER_EXECUTION_CONFIRMATION_GATE', 'tool' => $tool, 'mutation' => $mutation];
        }

        return [
            'ok' => true,
            'status' => 'RUNNER_EXECUTION_PLAN_READY',
            'tool' => $tool,
            'arguments' => $dispatchEnvelope['arguments'] ?? [],
            'allowedMode' => 'read_only',
            'hostCallRequired' => true,
            'resultMapping' => [
                'ok=true' => '--dispatch-status=ok',
                'ok=false' => '--dispatch-status=failed',
                'taskId' => '--external-task-id',
                'chatId' => '--external-chat-id',
                'targetId' => '--external-target-id',
            ],
        ];
    }
}
