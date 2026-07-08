<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 *
 * NOTE: not currently invoked. bin/console -> ChatGptLoopRunCommand drives an untyped,
 * array-based state/dispatch model built inline in the command itself. This class instead
 * belongs to a separate, internally consistent typed model (App\State\ChatGptTaskState,
 * App\Entity\ChatGptTask, App\Entity\ChatGptLifecycleRun, App\Dto\ChatGptNextAction,
 * App\Dto\ChatGptTranscriptRef) that isn't wired into the live command path yet. Left in place
 * rather than deleted, since removing it in isolation would leave that typed model even more
 * incomplete without actually retiring it. Whoever picks this up next: either finish wiring the
 * typed model into ChatGptLoopRunCommand and delete the inline array duplicate, or delete this
 * whole typed side entirely - don't let both keep drifting in parallel.
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
