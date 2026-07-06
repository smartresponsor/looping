<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

final class ConsoleMcpCapabilityMap
{
    public function forProductCommand(string $command): array
    {
        if (preg_match('/^cmcp\s+go\s+([a-z0-9_-]+)$/i', trim($command), $match) !== 1) {
            return [
                'ok' => false,
                'status' => 'UNSUPPORTED_PRODUCT_COMMAND',
                'command' => $command,
            ];
        }

        $component = strtolower($match[1]);

        return [
            'ok' => true,
            'status' => 'DELEGATION_PLAN_READY',
            'component' => $component,
            'preset' => 'repo_rc_implementation',
            'workspacePath' => 'D:\\PhpstormProjects\\www\\' . $component,
            'stages' => [
                'entrypoint_plan',
                'task_bank_resume_or_enqueue',
                'bounded_worker_tick',
                'chat_bind',
                'prompt_draft_submit',
                'answer_capture',
                'gateway_decision',
                'reply_back',
                'recovery_or_prune',
            ],
            'confirmationRequired' => true,
        ];
