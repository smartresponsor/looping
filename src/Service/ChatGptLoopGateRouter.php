<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopGateRouter
{
    public function route(array $evidence, array $repoFactSnapshot): array
    {
        $kind = (string) ($evidence['kind'] ?? 'unknown');
        $changedFiles = $repoFactSnapshot['changedFiles'] ?? [];
        $changedFiles = is_array($changedFiles) ? $changedFiles : [];

        if (!in_array($kind, ['commit_created', 'diff_created'], true)) {
            return [
                'ok' => true,
                'status' => 'GATE_ROUTE_SKIPPED',
                'reason' => 'No implementation evidence requires gates.',
                'plannedGates' => [],
                'nextAction' => $evidence['nextAction'] ?? 'ask_gateway_intent_review',
            ];
        }

        $plannedGates = [
            $this->gate('repo_status', 'required', 'Verify repository state after implementation.'),
            $this->gate('policy_implementation_admission', 'required', 'Verify implementation admission policy facts.'),
            $this->gate('component_gating_folder', 'optional', 'Run repository-local gating folder when present.'),
            $this->gate('composer_scripts', 'optional', 'Run component Composer scripts when present.'),
        ];

        if ($this->hasExtension($changedFiles, '.php')) {
            $plannedGates[] = $this->gate('php_lint_changed', 'required', 'Lint changed PHP files.');
        }

        if ($this->hasExtension($changedFiles, '.ts') || $this->hasExtension($changedFiles, '.tsx') || $this->hasExtension($changedFiles, '.js')) {
            $plannedGates[] = $this->gate('frontend_checks', 'optional', 'Run frontend checks when package scripts are available.');
        }

        return [
            'ok' => true,
            'status' => 'GATE_ROUTE_READY',
            'reason' => 'Implementation evidence requires gates.',
            'plannedGates' => $plannedGates,
            'plannedGateCount' => count($plannedGates),
            'nextAction' => 'run_tolerant_gates',
        ];
    }

    private function gate(string $name, string $requirement, string $reason): array
    {
        return [
            'name' => $name,
            'requirement' => $requirement,
            'reason' => $reason,
        ];
    }

    private function hasExtension(array $files, string $extension): bool
    {
        foreach ($files as $file) {
            if (is_string($file) && str_ends_with(strtolower($file), $extension)) {
                return true;
            }
        }

        return false;
    }
}
