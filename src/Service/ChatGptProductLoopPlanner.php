<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

final class ChatGptProductLoopPlanner
{
    public function plan(string $command, string $mode): array
    {
        $delegation = (new ConsoleMcpCapabilityMap())->forProductCommand($command);

        if (($delegation['ok'] ?? false) !== true) {
            return $delegation + ['mode' => $mode];
        }

        return [
            'ok' => true,
            'status' => 'PRODUCT_LOOP_PLAN_READY',
            'mode' => $mode,
            'productCommand' => $command,
            'delegation' => $delegation,
            'taskBankPolicy' => [
                'preferResume' => true,
                'identityOrder' => ['task_id', 'chat_id', 'target_id', 'component_workspace'],
                'pruneRequiresExplicitMissingChatConfirmation' => true,
            ],
            'nextAction' => 'Run entrypoint plan, then resume or enqueue the engine task.',
        ];
    }
}
