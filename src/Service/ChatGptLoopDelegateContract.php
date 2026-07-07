<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

final class ChatGptLoopDelegateContract
{
    public function describe(string $stage, array $request): array
    {
        $map = $this->map();

        if (!isset($map[$stage])) {
            return [
                'ok' => false,
                'status' => 'DELEGATE_CONTRACT_NOT_FOUND',
                'stage' => $stage,
                'knownStages' => array_keys($map),
            ];
        }

        return [
            'ok' => true,
            'status' => 'DELEGATE_CONTRACT_READY',
            'stage' => $stage,
            'contract' => $map[$stage],
            'arguments' => $this->argumentsFor($stage, $request),
            'execution' => 'external_console_mcp_required',
        ];
    }

    private function argumentsFor(string $stage, array $request): array
    {
        $component = (string) ($request['component'] ?? '');
        $workspacePath = (string) ($request['workspacePath'] ?? '');
        $preset = (string) ($request['preset'] ?? 'repo_rc_implementation');
        $budget = is_array($request['loopBudget'] ?? null) ? $request['loopBudget'] : [];

        return match ($stage) {
            'entrypoint_plan' => [
                'rawPrompt' => 'cmcp go ' . $component,
                'workspacePath' => $workspacePath,
                'componentName' => ucfirst($component),
                'taskPreset' => $preset,
                'maxAutoIterations' => $budget['maxIterations'] ?? null,
                'lifecycleTarget' => ($budget['untilRc'] ?? false) === true ? 'rc_complete' : 'bounded',
            ],
            'task_bank_resume_or_enqueue' => [
                'component' => ucfirst($component),
                'live' => false,
            ],
            'bounded_worker_tick' => [
                'maxTicks' => 1,
                'stopOnIdle' => true,
                'stopOnWaitingUser' => true,
                'budgetMode' => $budget['mode'] ?? 'single_step',
                'remainingBudget' => $budget['maxIterations'] ?? null,
            ],
            default => [
                'component' => $component,
                'workspacePath' => $workspacePath,
            ],
        };
    }

    private function map(): array
    {
        return [
            'entrypoint_plan' => ['capability' => 'browser.chatgpt.entrypoint.plan', 'mutation' => 'none', 'confirmation' => false],
            'task_bank_resume_or_enqueue' => ['capability' => 'engine.task.enqueue', 'mutation' => 'engine_bank', 'confirmation' => true],
            'bounded_worker_tick' => ['capability' => 'engine.worker.tick', 'mutation' => 'engine_bank', 'confirmation' => true],
            'chat_bind' => ['capability' => 'engine.chat.bind', 'mutation' => 'browser_binding', 'confirmation' => true],
            'prompt_draft_submit' => ['capability' => 'engine.prompt.draft_submit', 'mutation' => 'browser_composer', 'confirmation' => true],
            'answer_capture' => ['capability' => 'engine.answer.capture', 'mutation' => 'engine_bank', 'confirmation' => true],
            'gateway_decision' => ['capability' => 'engine.gateway.decide', 'mutation' => 'engine_bank', 'confirmation' => true],
            'reply_back' => ['capability' => 'engine.reply.sequence', 'mutation' => 'browser_composer', 'confirmation' => true],
            'recovery_or_prune' => ['capability' => 'browser.session.run.loop.recover', 'mutation' => 'engine_bank', 'confirmation' => true],
        ];
    }
}
