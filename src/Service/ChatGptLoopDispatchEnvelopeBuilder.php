<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopDispatchEnvelopeBuilder
{
    public function build(?array $delegateRequest): ?array
    {
        if ($delegateRequest === null || ($delegateRequest['ok'] ?? false) !== true) {
            return null;
        }

        $contract = $delegateRequest['contract'] ?? [];
        $request = $delegateRequest['request'] ?? [];
        $contractBody = is_array($contract['contract'] ?? null) ? $contract['contract'] : [];
        $arguments = is_array($contract['arguments'] ?? null) ? $contract['arguments'] : [];
        $capability = (string) ($contractBody['capability'] ?? '');

        return [
            'ok' => $capability !== '',
            'status' => $capability !== '' ? 'DISPATCH_ENVELOPE_READY' : 'DISPATCH_ENVELOPE_NOT_AVAILABLE',
            'stage' => (string) ($request['stage'] ?? ''),
            'capability' => $capability,
            'tool' => $this->toolName($capability),
            'arguments' => $arguments,
            'confirmationRequired' => ($contractBody['confirmation'] ?? true) === true,
            'mutation' => (string) ($contractBody['mutation'] ?? 'unknown'),
            'execution' => 'external_console_mcp_required',
        ];
    }

    private function toolName(string $capability): ?string
    {
        return match ($capability) {
            'browser.chatgpt.entrypoint.plan' => 'console.read_.browser.chatgpt.entrypoint.plan',
            'engine.task.enqueue' => 'console.write.engine.task.enqueue',
            'engine.worker.tick' => 'console.write.engine.worker.tick',
            'engine.chat.bind' => 'console.write.engine.chat.bind',
            'engine.answer.capture' => 'console.write.engine.answer.capture',
            'engine.gateway.decide' => 'console.write.engine.gateway.decide',
            default => null,
        };
    }
}
