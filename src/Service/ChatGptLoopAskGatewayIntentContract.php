<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopAskGatewayIntentContract
{
    public function build(string $task, array $evidence, array $feedback, array $loopDecision): array
    {
        if (($loopDecision['action'] ?? null) !== 'ask_gateway_review') {
            return [
                'ok' => true,
                'status' => 'ASK_GATEWAY_INTENT_CONTRACT_SKIPPED',
                'reason' => 'Loop decision does not require Ask/Gateway intent review.',
                'payload' => null,
            ];
        }

        return [
            'ok' => true,
            'status' => 'ASK_GATEWAY_INTENT_CONTRACT_READY',
            'target' => 'ask_gateway',
            'purpose' => 'intent_risk_review',
            'payload' => [
                'task' => $task,
                'intentEvidence' => [
                    'status' => $evidence['status'] ?? null,
                    'kind' => $evidence['kind'] ?? null,
                    'confidence' => $evidence['confidence'] ?? null,
                    'reason' => $evidence['reason'] ?? null,
                ],
                'feedback' => [
                    'status' => $feedback['status'] ?? null,
                    'summary' => $feedback['summary'] ?? null,
                    'messages' => $feedback['messages'] ?? [],
                ],
                'question' => 'Review this implementation intent against canon and policy. Decide whether the loop may continue, must warn, must revise, or must block.',
                'expectedVerdict' => [
                    'allow',
                    'warn',
                    'revise',
                    'block',
                ],
                'requiredReturnFields' => [
                    'verdict',
                    'risks',
                    'policyReferences',
                    'messageToChat',
                    'nextAction',
                ],
            ],
            'nextAction' => 'send_payload_to_ask_gateway',
        ];
    }
}
