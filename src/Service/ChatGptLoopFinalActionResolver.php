<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopFinalActionResolver
{
    public function resolve(array $loopDecision, array $askGatewayDecision, array $chatResponsePayload, array $chatResponseDispatchContract): array
    {
        $loopAction = (string) ($loopDecision['action'] ?? 'wait_or_review');
        $askAction = (string) ($askGatewayDecision['action'] ?? $loopAction);
        $shouldSend = ($chatResponsePayload['shouldSend'] ?? false) === true;
        $dispatchReady = ($chatResponseDispatchContract['status'] ?? null) === 'CHAT_RESPONSE_DISPATCH_CONTRACT_READY';
        $dispatchMissingTarget = ($chatResponseDispatchContract['status'] ?? null) === 'CHAT_RESPONSE_DISPATCH_TARGET_MISSING';

        if ($shouldSend && $dispatchMissingTarget) {
            return $this->action(false, 'FINAL_ACTION_RESPONSE_TARGET_REQUIRED', 'provide_response_chat_id', 'A chat response must be sent, but response chat id is missing.');
        }

        if ($shouldSend && $dispatchReady) {
            return $this->action(true, 'FINAL_ACTION_DISPATCH_CHAT_RESPONSE', 'dispatch_chat_response', 'A chat response payload is ready and has a dispatch envelope.');
        }

        if (in_array($askAction, ['stop_blocked_by_policy', 'return_revision_request_to_chat', 'return_warning_then_continue', 'return_invalid_ask_result'], true)) {
            return $this->action(false, 'FINAL_ACTION_CHAT_RESPONSE_REQUIRED', 'build_or_dispatch_chat_response', 'Ask/Gateway requires a chat response but no ready dispatch envelope was produced.');
        }

        if ($askAction === 'wait_for_ask_gateway_result') {
            return $this->action(true, 'FINAL_ACTION_WAIT_FOR_ASK', 'wait_for_ask_gateway_result', 'Ask/Gateway review is required and the loop is waiting for its result.');
        }

        if ($askAction === 'continue' || $loopAction === 'continue') {
            return $this->action(true, 'FINAL_ACTION_CONTINUE', 'continue_loop', 'The loop may continue to the next iteration.');
        }

        if (str_starts_with($loopAction, 'stop')) {
            return $this->action(false, 'FINAL_ACTION_STOP', $loopAction, $loopDecision['reason'] ?? 'Loop stop action selected.');
        }

        return $this->action(true, 'FINAL_ACTION_WAIT_OR_REVIEW', 'wait_or_review', 'No explicit continuation or dispatch action was selected.');
    }

    private function action(bool $ok, string $status, string $action, string $reason): array
    {
        return [
            'ok' => $ok,
            'status' => $status,
            'action' => $action,
            'reason' => $reason,
        ];
    }
}
