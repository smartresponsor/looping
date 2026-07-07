<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopChatResponseDispatchContract
{
    public function build(array $chatResponsePayload, array $options): array
    {
        if (($chatResponsePayload['shouldSend'] ?? false) !== true) {
            return [
                'ok' => true,
                'status' => 'CHAT_RESPONSE_DISPATCH_SKIPPED',
                'reason' => 'Chat response payload does not require sending.',
                'envelope' => null,
            ];
        }

        $taskId = $this->stringOrNull($options['response-task-id'] ?? $options['external-task-id'] ?? $options['host-task-id'] ?? null);
        $targetId = $this->stringOrNull($options['response-target-id'] ?? $options['external-target-id'] ?? $options['host-target-id'] ?? null);

        if ($taskId === null) {
            return [
                'ok' => false,
                'status' => 'CHAT_RESPONSE_DISPATCH_TASK_MISSING',
                'reason' => 'Engine task id is required before dispatching a canonical reply-back response.',
                'envelope' => null,
                'sequence' => [],
                'nextAction' => 'provide_response_task_id',
            ];
        }

        return [
            'ok' => true,
            'status' => 'CHAT_RESPONSE_DISPATCH_CONTRACT_READY',
            'reason' => 'Canonical engine reply-back draft and submit sequence is ready.',
            'envelope' => null,
            'sequence' => [
                [
                    'stage' => 'reply_draft',
                    'tool' => 'console.write.engine.reply.draft',
                    'arguments' => [
                        'taskId' => $taskId,
                        'expectedTargetId' => $targetId,
                        'allowOverwrite' => false,
                        'confirmDraft' => true,
                    ],
                    'mutation' => 'write',
                    'confirmationRequired' => false,
                    'execution' => 'external_console_mcp_required',
                ],
                [
                    'stage' => 'reply_submit',
                    'tool' => 'console.write.engine.reply.submit',
                    'arguments' => [
                        'taskId' => $taskId,
                        'expectedTargetId' => $targetId,
                        'confirmSubmit' => true,
                    ],
                    'mutation' => 'write',
                    'confirmationRequired' => false,
                    'execution' => 'external_console_mcp_required',
                ],
            ],
            'nextAction' => 'dispatch_chat_response',
        ];
    }

    private function stringOrNull(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : $trimmed;
    }
}
