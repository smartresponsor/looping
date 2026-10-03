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

        $allowedTools = [
            'read_.browser.chatgpt.entrypoint.plan' => 'read_only',
            'write.engine.task.enqueue' => 'write',
            'write.engine.worker.tick' => 'write',
            'write.engine.chat.bind' => 'write',
            'write.engine.answer.capture' => 'write',
            'write.engine.gateway.decide' => 'write',
            'write.engine.reply.draft' => 'write',
            'write.engine.reply.submit' => 'write',
        ];

        if (!array_key_exists($tool, $allowedTools)) {
            return ['ok' => false, 'status' => 'RUNNER_EXECUTION_TOOL_NOT_ALLOWED', 'tool' => $tool];
        }

        return [
            'ok' => true,
            'status' => 'RUNNER_EXECUTION_PLAN_READY',
            'tool' => $tool,
            'arguments' => $dispatchEnvelope['arguments'] ?? [],
            'allowedMode' => $allowedTools[$tool],
            'mutation' => $mutation,
            'confirmationRequired' => $confirmationRequired,
            'confirmationGate' => 'disabled',
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
