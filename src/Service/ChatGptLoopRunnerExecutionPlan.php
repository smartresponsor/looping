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
            'console.read_.browser.chatgpt.entrypoint.plan' => 'read_only',
            'console.write.engine.task.enqueue' => 'write',
            'console.write.engine.worker.tick' => 'write',
            'console.write.engine.chat.bind' => 'write',
            'console.write.engine.answer.capture' => 'write',
            'console.write.engine.gateway.decide' => 'write',
            'console.write.engine.reply.draft_submit' => 'write',
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
