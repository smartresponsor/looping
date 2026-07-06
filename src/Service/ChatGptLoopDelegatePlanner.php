<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

use App\Dto\ChatGptLoopDelegateRequest;

final class ChatGptLoopDelegatePlanner
{
    public function create(array $productPlan, string $requestedStage): array
    {
        $delegation = $productPlan['delegation'] ?? [];
        $stages = $delegation['stages'] ?? [];

        if (!is_array($delegation) || !is_array($stages) || !in_array($requestedStage, $stages, true)) {
            return [
                'ok' => false,
                'status' => 'DELEGATE_STAGE_NOT_AVAILABLE',
                'requestedStage' => $requestedStage,
                'availableStages' => is_array($stages) ? $stages : [],
            ];
        }

        $request = new ChatGptLoopDelegateRequest(
            $requestedStage,
            (string) ($delegation['component'] ?? ''),
            (string) ($delegation['workspacePath'] ?? ''),
            (string) ($delegation['preset'] ?? ''),
            true,
        );

        $requestArray = $request->toArray();

        return [
            'ok' => true,
            'status' => 'DELEGATE_REQUEST_READY',
            'request' => $requestArray,
            'contract' => (new ChatGptLoopDelegateContract())->describe($requestedStage, $requestArray),
            'execution' => 'external_console_mcp_required',
        ];
    }
}
