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
                'console.read_.browser.chatgpt.entrypoint.plan' => 'read_only',
                'console.write.engine.task.enqueue' => 'write',
                'console.write.engine.worker.tick' => 'write',
                'console.write.engine.chat.bind' => 'write',
                'console.write.engine.answer.capture' => 'write',
                'console.write.engine.gateway.decide' => 'write',
                'console.write.engine.reply.draft' => 'write',
                'console.write.engine.reply.submit' => 'write',
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
