<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopResumeStateBuilder
{
    public function build(?array $dispatchResult, array $routePlan): array
    {
        if ($dispatchResult === null) {
            return [
                'ok' => true,
                'status' => 'RESUME_STATE_PENDING_DISPATCH',
                'currentStage' => $routePlan['nextDelegateStage'] ?? null,
                'nextAction' => 'dispatch_envelope',
            ];
        }

        $accepted = ($dispatchResult['status'] ?? '') === 'DISPATCH_RESULT_ACCEPTED';
        $blocked = ($dispatchResult['status'] ?? '') === 'DISPATCH_RESULT_BLOCKED';

        return [
            'ok' => $accepted,
            'status' => $accepted ? 'RESUME_STATE_ADVANCED' : ($blocked ? 'RESUME_STATE_BLOCKED' : 'RESUME_STATE_FAILED'),
            'currentStage' => $dispatchResult['stage'] ?? ($routePlan['nextDelegateStage'] ?? null),
            'externalTaskId' => $dispatchResult['externalTaskId'] ?? null,
            'externalChatId' => $dispatchResult['externalChatId'] ?? null,
            'externalTargetId' => $dispatchResult['externalTargetId'] ?? null,
            'nextAction' => $accepted ? 'continue_route' : ($blocked ? 'wait_or_recover' : 'inspect_failure'),
        ];
    }
}
