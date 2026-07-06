<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

use App\Dto\ChatGptNextAction;
use App\Dto\ChatGptPromptDispatchResult;
use App\Enum\ChatGptLoopStatus;

final class ChatGptNextActionFactory
{
    public function create(ChatGptPromptDispatchResult $result, ?string $bang): ChatGptNextAction
    {
        if ($result->status === ChatGptLoopStatus::BackendNotConfigured) {
            return new ChatGptNextAction(
                code: 'CONFIGURE_EXECUTION_BACKEND',
                label: 'Configure ChatGPT dispatch backend',
                reason: 'The loop can persist lifecycle state, but real prompt dispatch is not connected yet.',
            );
        }

        if ($bang === null) {
            return new ChatGptNextAction(
                code: 'CLASSIFY_TASK_BANG',
                label: 'Classify task bang',
                reason: 'The task has no explicit bang and should be classified before automated dispatch.',
            );
        }

        return new ChatGptNextAction(
            code: 'WAIT_FOR_RESULT',
            label: 'Wait for ChatGPT result',
            reason: 'The dispatch request was accepted by the configured backend.',
        );
    }
}
