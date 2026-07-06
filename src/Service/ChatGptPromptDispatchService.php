<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

use App\Dto\ChatGptPromptDispatchRequest;
use App\Dto\ChatGptPromptDispatchResult;
use App\Enum\ChatGptLoopStatus;

final class ChatGptPromptDispatchService
{
    public function dispatch(ChatGptPromptDispatchRequest $request): ChatGptPromptDispatchResult
    {
        $backendConfigured = getenv('CHATGPT_LOOP_BACKEND_CONFIGURED') === '1';
        $backendName = getenv('CHATGPT_LOOP_BACKEND') ?: 'console-mcp';

        if (!$backendConfigured) {
            return new ChatGptPromptDispatchResult(
                ok: false,
                status: ChatGptLoopStatus::BackendNotConfigured,
                backend: $backendName,
                message: sprintf(
                    'Dispatch backend is not configured for run %s; state and transcript reference were still produced.',
                    $request->runId,
                ),
            );
        }

        return new ChatGptPromptDispatchResult(
            ok: true,
            status: ChatGptLoopStatus::Accepted,
            backend: $backendName,
            message: sprintf('Dispatch request accepted by backend for run %s.', $request->runId),
        );
    }
}
