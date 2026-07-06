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

        $chatId = $this->stringOrNull($options['response-chat-id'] ?? $options['external-chat-id'] ?? $options['host-chat-id'] ?? null);
        $targetId = $this->stringOrNull($options['response-target-id'] ?? $options['external-target-id'] ?? $options['host-target-id'] ?? null);

        return [
            'ok' => $chatId !== null,
            'status' => $chatId === null ? 'CHAT_RESPONSE_DISPATCH_TARGET_MISSING' : 'CHAT_RESPONSE_DISPATCH_CONTRACT_READY',
            'reason' => $chatId === null ? 'Response chat id is required before dispatching a chat response.' : 'Chat response dispatch envelope is ready.',
            'envelope' => [
                'tool' => 'console.write.engine.reply.draft_submit',
                'arguments' => [
                    'chatId' => $chatId,
                    'targetId' => $targetId,
                    'message' => (string) ($chatResponsePayload['message'] ?? ''),
                    'action' => $chatResponsePayload['action'] ?? null,
                ],
                'mutation' => 'write',
                'confirmationRequired' => false,
                'execution' => 'external_console_mcp_required',
            ],
            'nextAction' => $chatId === null ? 'provide_response_chat_id' : 'dispatch_chat_response',
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
