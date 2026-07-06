<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopHostResultBridge
{
    public function build(array $hostResult, array $runnerExecutionPlan, string $task): array
    {
        $ok = ($hostResult['ok'] ?? false) === true;
        $dispatchStatus = $ok ? 'ok' : 'failed';
        $taskId = $hostResult['taskId'] ?? ($hostResult['task_id'] ?? null);
        $chatId = $hostResult['chatId'] ?? ($hostResult['chat_id'] ?? null);
        $targetId = $hostResult['targetId'] ?? ($hostResult['target_id'] ?? null);

        $args = [
            'bin/console',
            'chatgpt-loop:run',
            '--task=' . $task,
            '--dispatch-status=' . $dispatchStatus,
        ];

        if (is_string($taskId) && $taskId !== '') {
            $args[] = '--external-task-id=' . $taskId;
        }
        if (is_string($chatId) && $chatId !== '') {
            $args[] = '--external-chat-id=' . $chatId;
        }
        if (is_string($targetId) && $targetId !== '') {
            $args[] = '--external-target-id=' . $targetId;
        }

        return [
            'ok' => true,
            'status' => 'HOST_RESULT_BRIDGE_READY',
            'hostOk' => $ok,
            'dispatchStatus' => $dispatchStatus,
            'tool' => $runnerExecutionPlan['tool'] ?? null,
            'continueCommand' => 'php ' . implode(' ', array_map([$this, 'quoteArg'], $args)),
            'continueArgs' => $args,
        ];
    }

    private function quoteArg(string $value): string
    {
        if (preg_match('/^[A-Za-z0-9_\\-\\.\\:\\\\=]+$/', $value) === 1) {
            return $value;
        }

        return '"' . str_replace('"', '\\"', $value) . '"';
    }
}
