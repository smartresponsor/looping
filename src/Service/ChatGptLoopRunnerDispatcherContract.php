<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopRunnerDispatcherContract
{
    public function describe(): array
    {
        return [
            'ok' => true,
            'status' => 'RUNNER_DISPATCHER_CONTRACT_READY',
            'input' => [
                'tool' => 'runnerExecutionPlan.tool',
                'arguments' => 'runnerExecutionPlan.arguments',
                'allowedMode' => 'runnerExecutionPlan.allowedMode',
                'mutation' => 'runnerExecutionPlan.mutation',
                'confirmationGate' => 'runnerExecutionPlan.confirmationGate',
            ],
            'output' => [
                'ok' => 'boolean',
                'taskId' => 'string|null',
                'chatId' => 'string|null',
                'targetId' => 'string|null',
                'raw' => 'array|null',
            ],
            'allowedTools' => [
                'read_.browser.chatgpt.entrypoint.plan' => 'read_only',
                'write.engine.task.enqueue' => 'write',
                'write.engine.worker.tick' => 'write',
                'write.engine.chat.bind' => 'write',
                'write.engine.answer.capture' => 'write',
                'write.engine.gateway.decide' => 'write',
                'write.engine.reply.draft' => 'write',
                'write.engine.reply.submit' => 'write',
            ],
            'resultBridge' => [
                'ok=true' => '--host-result-ok=1',
                'ok=false' => '--host-result-ok=0',
                'taskId' => '--host-task-id',
                'chatId' => '--host-chat-id',
                'targetId' => '--host-target-id',
            ],
            'nextAction' => 'host_dispatcher_invokes_allowlisted_console_mcp_tool',
        ];
    }
}
