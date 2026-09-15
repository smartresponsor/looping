<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopCompletionVerificationPlanner
{
    public function plan(array $task, array $checkNames = [], bool $behavioralRequired = false, array $capabilities = []): array
    {
        $workspacePath = $this->string($task['workspace_path'] ?? $task['workspacePath'] ?? null);
        $beforeHead = $this->string($task['initial_head'] ?? $task['beforeHead'] ?? null);
        if ($workspacePath === null || $beforeHead === null) {
            return [
                'ok' => false,
                'status' => 'COMPLETION_VERIFICATION_PLAN_INCOMPLETE',
                'authoritative' => false,
                'runtimeEffect' => 'none',
                'blockers' => ['workspace_or_baseline_head_missing'],
                'contracts' => [],
                'readyForM5Execution' => false,
            ];
        }

        $contracts = [
            [
                'tool' => 'console.read_.repo.workspace.status',
                'arguments' => ['workspacePath' => $workspacePath],
                'mutation' => 'read',
            ],
            [
                'tool' => 'console.read_.repo.git.branch.status',
                'arguments' => ['workspacePath' => $workspacePath],
                'mutation' => 'read',
            ],
            [
                'tool' => 'console.read_.repo.implementation.run.capture',
                'arguments' => [
                    'workspacePath' => $workspacePath,
                    'beforeHead' => $beforeHead,
                    'checkNames' => array_values($checkNames),
                    'includeDiff' => true,
                    'diffMaxChars' => 30000,
                    'maxCommits' => 30,
                ],
                'mutation' => 'read',
            ],
            [
                'tool' => 'console.read_.repo.gate.check.run',
                'arguments' => ['workspacePath' => $workspacePath, 'checkName' => 'git_diff_check'],
                'mutation' => 'read',
            ],
        ];

        $blockers = [];
        if (($capabilities['gitDiffCheckRuntimeActive'] ?? false) !== true) {
            $blockers[] = 'git_diff_check_runtime_restart_pending';
        }
        if ($behavioralRequired && ($capabilities['behavioralEvidenceExecutorReady'] ?? false) !== true) {
            $blockers[] = 'behavioral_visual_evidence_executor_not_copied';
        }
        $ready = $blockers === [];

        return [
            'ok' => true,
            'status' => $ready ? 'COMPLETION_VERIFICATION_PLAN_READY' : 'COMPLETION_VERIFICATION_PLAN_BLOCKED',
            'authoritative' => false,
            'runtimeEffect' => 'none',
            'contracts' => $contracts,
            'blockers' => $blockers,
            'readyForM5Execution' => $ready,
        ];
    }

    private function string(mixed $value): ?string
    {
        return is_string($value) && trim($value) !== '' ? trim($value) : null;
    }
}
