<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopAskGatewayResultIntake
{
    public function fromOptions(array $options): array
    {
        $verdict = $this->stringOrNull($options['ask-verdict'] ?? null);

        if ($verdict === null) {
            return [
                'ok' => true,
                'status' => 'ASK_GATEWAY_RESULT_NOT_PROVIDED',
                'verdict' => null,
                'nextAction' => 'wait_for_ask_gateway_result',
            ];
        }

        $verdict = strtolower($verdict);
        $allowed = ['allow', 'warn', 'revise', 'block'];

        if (!in_array($verdict, $allowed, true)) {
            return [
                'ok' => false,
                'status' => 'ASK_GATEWAY_RESULT_INVALID',
                'verdict' => $verdict,
                'nextAction' => 'return_invalid_ask_result',
            ];
        }

        return [
            'ok' => $verdict !== 'block',
            'status' => 'ASK_GATEWAY_RESULT_READY',
            'verdict' => $verdict,
            'risks' => $this->csv($options['ask-risks'] ?? null),
            'policyReferences' => $this->csv($options['ask-policy-references'] ?? null),
            'messageToChat' => $this->stringOrNull($options['ask-message-to-chat'] ?? null),
            'nextAction' => $this->mapNextAction($verdict, $this->stringOrNull($options['ask-next-action'] ?? null)),
        ];
    }

    private function mapNextAction(string $verdict, ?string $provided): string
    {
        if ($provided !== null) {
            return $provided;
        }

        return match ($verdict) {
            'allow' => 'continue_loop',
            'warn' => 'return_warning_then_continue',
            'revise' => 'return_revision_request_to_chat',
            'block' => 'stop_blocked_by_policy',
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

    private function csv(mixed $value): array
    {
        if (!is_string($value) || trim($value) === '') {
            return [];
        }

        return array_values(array_filter(array_map('trim', explode(',', $value)), static fn (string $item): bool => $item !== ''));
    }
}
