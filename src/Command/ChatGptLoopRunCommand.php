<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Command;

use InvalidArgumentException;
use Throwable;

final class ChatGptLoopRunCommand
{
    public function __construct(private readonly string $projectDir)
    {
    }

    public function run(array $args): int
    {
        try {
            $options = $this->parseOptions($args);
            $task = trim($options['task'] ?? '');
            $mode = $options['mode'] ?? 'diagnostic';
            $planOnly = ($options['plan-only'] ?? '0') === '1';
            $delegateStage = $options['delegate'] ?? null;
            $loopBudget = \App\Dto\ChatGptLoopBudget::fromOptions($options);

            if ($task === '') {
                throw new InvalidArgumentException('The --task option is required.');
            }

            $productPlan = (new \App\Service\ChatGptProductLoopPlanner())->plan($task, $mode);
            $routePlan = (new \App\Service\ChatGptLoopRoutePlanner())->plan($productPlan, $loopBudget->toArray(), is_string($delegateStage) ? $delegateStage : null);
            $delegateRequest = null;

            if (is_string($delegateStage) && $delegateStage !== '') {
                $delegateRequest = (new \App\Service\ChatGptLoopDelegatePlanner())->create($productPlan, $delegateStage, $loopBudget->toArray());
            }

            $createdAt = gmdate('c');
            $taskId = 'task_' . substr(hash('sha256', $task . $createdAt), 0, 16);
            $runId = 'run_' . gmdate('Ymd_His') . '_' . substr(hash('sha256', $taskId . microtime(true)), 0, 12);
            $bang = null;
            $body = $task;

            if (str_starts_with($task, '!')) {
                [$head, $tail] = array_pad(preg_split('/\s+/', $task, 2), 2, '');
                $bang = ltrim($head, '!');
                $body = trim($tail);
            }

            $backend = getenv('CHATGPT_LOOP_BACKEND') ?: 'console-mcp';
            $ok = $planOnly || $delegateRequest !== null || getenv('CHATGPT_LOOP_BACKEND_CONFIGURED') === '1';
            $status = $planOnly ? 'PLAN_ONLY_READY' : ($delegateRequest !== null ? 'DELEGATE_READY' : ($ok ? 'ACCEPTED' : 'BACKEND_NOT_CONFIGURED'));
            $nextAction = $ok ? [
                'code' => 'WAIT_FOR_RESULT',
                'label' => 'Wait for ChatGPT result',
                'reason' => 'The backend accepted the request.',
            ] : [
                'code' => 'CONFIGURE_EXECUTION_BACKEND',
                'label' => 'Configure ChatGPT backend',
                'reason' => 'The loop persisted state, but real execution is not connected yet.',
            ];

            $statePath = $this->writeJson('state', $runId, [
                'task' => ['id' => $taskId, 'rawText' => $task, 'bang' => $bang, 'body' => $body],
                'run' => ['id' => $runId, 'taskId' => $taskId, 'mode' => $mode, 'createdAt' => $createdAt],
                'loopBudget' => $loopBudget->toArray(),
                'result' => ['ok' => $ok, 'status' => $status, 'backend' => $backend],
                'productPlan' => $productPlan,
                'routePlan' => $routePlan,
                'delegateRequest' => $delegateRequest,
                'nextAction' => $nextAction,
            ]);
            $transcriptPath = $this->writeJson('transcript', $runId, [
                'runId' => $runId,
                'createdAt' => $createdAt,
                'request' => ['taskId' => $taskId, 'mode' => $mode, 'task' => $body, 'bang' => $bang],
                'loopBudget' => $loopBudget->toArray(),
                'productPlan' => $productPlan,
                'routePlan' => $routePlan,
                'delegateRequest' => $delegateRequest,
                'result' => ['ok' => $ok, 'status' => $status, 'backend' => $backend],
            ]);

            return $this->printJson([
                'ok' => $ok,
                'status' => $status,
                'runId' => $runId,
                'taskId' => $taskId,
                'mode' => $mode,
                'loopBudget' => $loopBudget->toArray(),
                'statePath' => $statePath,
                'transcriptPath' => $transcriptPath,
                'productPlan' => $productPlan,
                'routePlan' => $routePlan,
                'delegateRequest' => $delegateRequest,
                'nextAction' => $nextAction,
                'backend' => $backend,
                'createdAt' => $createdAt,
            ], STDOUT, 0);
        } catch (Throwable $exception) {
            return $this->printJson(['ok' => false, 'status' => 'FAILED', 'error' => $exception->getMessage()], STDERR, 1);
        }
    }

    private function writeJson(string $type, string $runId, array $payload): string
    {
        $dir = $this->projectDir . '/var/' . $type;
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new InvalidArgumentException('Unable to create directory: ' . $dir);
        }
        $path = $dir . '/' . $runId . '.json';
        file_put_contents($path, json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);

        return $path;
    }

    private function printJson(array $payload, mixed $stream, int $code): int
    {
        fwrite($stream, json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);

        return $code;
    }

    private function parseOptions(array $args): array
    {
        $options = [];
        foreach ($args as $arg) {
            if (str_starts_with($arg, '--')) {
                [$name, $value] = array_pad(explode('=', substr($arg, 2), 2), 2, '1');
                $options[$name] = $value;
            }
        }

        return $options;
    }
}
