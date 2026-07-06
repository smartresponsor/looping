<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopChatResponsePayloadBuilder
{
    public function build(array $feedback, array $loopDecision, array $askGatewayResult, array $askGatewayDecision): array
    {
        $action = (string) ($askGatewayDecision['action'] ?? $loopDecision['action'] ?? 'wait_or_review');
        $message = $this->messageForAction($action, $feedback, $askGatewayResult, $askGatewayDecision);

        return [
            'ok' => true,
            'status' => 'CHAT_RESPONSE_PAYLOAD_READY',
            'shouldSend' => $this->shouldSend($action),
            'action' => $action,
            'message' => $message,
            'metadata' => [
                'feedbackStatus' => $feedback['status'] ?? null,
                'loopDecisionStatus' => $loopDecision['status'] ?? null,
                'askGatewayStatus' => $askGatewayDecision['status'] ?? null,
                'askVerdict' => $askGatewayResult['verdict'] ?? null,
            ],
        ];
    }

    private function shouldSend(string $action): bool
    {
        return in_array($action, [
            'return_to_chat',
            'return_warning_then_continue',
            'return_revision_request_to_chat',
            'stop_blocked_by_policy',
            'stop',
            'stop_or_recover',
            'return_invalid_ask_result',
        ], true);
    }

    private function messageForAction(string $action, array $feedback, array $askGatewayResult, array $askGatewayDecision): string
    {
        $askMessage = $this->stringOrNull($askGatewayResult['messageToChat'] ?? null);
        if ($askMessage !== null) {
            return $askMessage;
        }

        $summary = $this->stringOrNull($feedback['summary'] ?? null) ?? $this->stringOrNull($askGatewayDecision['reason'] ?? null) ?? 'Loop decision requires attention.';
        $messages = $feedback['messages'] ?? [];
        $messages = is_array($messages) ? $messages : [];
        $body = $messages === [] ? $summary : $summary . PHP_EOL . '- ' . implode(PHP_EOL . '- ', array_map('strval', $messages));

        return match ($action) {
            'return_warning_then_continue' => 'Warning before continuing:' . PHP_EOL . $body,
            'return_revision_request_to_chat' => 'Revision required before continuing:' . PHP_EOL . $body,
            'stop_blocked_by_policy' => 'Blocked by policy review:' . PHP_EOL . $body,
            'stop', 'stop_or_recover' => 'Loop stopped:' . PHP_EOL . $body,
            'return_invalid_ask_result' => 'Ask/Gateway returned an invalid result. Please return a valid verdict: allow, warn, revise, or block.',
            'return_to_chat' => 'Required correction:' . PHP_EOL . $body,
            default => $body,
        };
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
