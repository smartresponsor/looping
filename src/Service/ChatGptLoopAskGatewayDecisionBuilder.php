<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopAskGatewayDecisionBuilder
{
    public function build(array $loopDecision, array $askGatewayResult): array
    {
        if (($loopDecision['action'] ?? null) !== 'ask_gateway_review') {
            return [
                'ok' => true,
                'status' => 'ASK_GATEWAY_DECISION_SKIPPED',
                'action' => $loopDecision['action'] ?? 'unknown',
                'reason' => 'Loop decision does not require Ask/Gateway result handling.',
            ];
        }

        if (($askGatewayResult['status'] ?? null) === 'ASK_GATEWAY_RESULT_NOT_PROVIDED') {
            return [
                'ok' => true,
                'status' => 'ASK_GATEWAY_DECISION_WAITING',
                'action' => 'wait_for_ask_gateway_result',
                'reason' => 'Ask/Gateway review is required but no result was provided yet.',
            ];
        }

        $verdict = (string) ($askGatewayResult['verdict'] ?? 'unknown');

        return match ($verdict) {
            'allow' => $this->decision(true, 'ASK_GATEWAY_DECISION_ALLOW', 'continue', 'Ask/Gateway allowed the intent to continue.'),
            'warn' => $this->decision(true, 'ASK_GATEWAY_DECISION_WARN', 'return_warning_then_continue', 'Ask/Gateway allowed continuation with warning.'),
            'revise' => $this->decision(false, 'ASK_GATEWAY_DECISION_REVISE', 'return_revision_request_to_chat', 'Ask/Gateway requires revision before continuation.'),
            'block' => $this->decision(false, 'ASK_GATEWAY_DECISION_BLOCK', 'stop_blocked_by_policy', 'Ask/Gateway blocked the intent.'),
            default => $this->decision(false, 'ASK_GATEWAY_DECISION_INVALID', 'return_invalid_ask_result', 'Ask/Gateway result is invalid.'),
        };
    }

    private function decision(bool $ok, string $status, string $action, string $reason): array
    {
        return [
            'ok' => $ok,
            'status' => $status,
            'action' => $action,
            'reason' => $reason,
        ];
    }
}
