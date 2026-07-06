<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopDispatchResultIntake
{
    public function fromOptions(array $options, ?array $dispatchEnvelope): ?array
    {
        $status = $options['dispatch-status'] ?? null;

        if (!is_string($status) || $status === '') {
            return null;
        }

        $normalizedStatus = strtolower($status);
        $ok = in_array($normalizedStatus, ['ok', 'complete', 'accepted'], true);
        $blocked = in_array($normalizedStatus, ['blocked', 'waiting_user'], true);

        return [
            'ok' => $ok,
            'status' => $ok ? 'DISPATCH_RESULT_ACCEPTED' : ($blocked ? 'DISPATCH_RESULT_BLOCKED' : 'DISPATCH_RESULT_FAILED'),
            'rawStatus' => $status,
            'stage' => is_array($dispatchEnvelope) ? ($dispatchEnvelope['stage'] ?? null) : null,
            'tool' => is_array($dispatchEnvelope) ? ($dispatchEnvelope['tool'] ?? null) : null,
            'externalTaskId' => $options['external-task-id'] ?? null,
            'externalChatId' => $options['external-chat-id'] ?? null,
            'externalTargetId' => $options['external-target-id'] ?? null,
            'nextAction' => $ok ? 'continue_route' : ($blocked ? 'wait_for_user_or_recovery' : 'inspect_dispatch_failure'),
        ];
    }
}
