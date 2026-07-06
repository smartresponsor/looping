<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopTolerantGatePlan
{
    public function build(array $gateRoute, array $options): array
    {
        $plannedGates = $gateRoute['plannedGates'] ?? [];
        $plannedGates = is_array($plannedGates) ? $plannedGates : [];
        $declaredAvailable = $this->csv($options['gate-available'] ?? null);
        $declaredPassed = $this->csv($options['gate-passed'] ?? null);
        $declaredFailed = $this->csv($options['gate-failed'] ?? null);
        $results = [];
        $failedRequired = 0;

        foreach ($plannedGates as $gate) {
            if (!is_array($gate)) {
                continue;
            }

            $name = (string) ($gate['name'] ?? 'unknown');
            $requirement = (string) ($gate['requirement'] ?? 'optional');
            $available = $declaredAvailable === [] || in_array($name, $declaredAvailable, true);
            $status = 'skipped_missing';

            if ($available && in_array($name, $declaredPassed, true)) {
                $status = 'passed';
            } elseif ($available && in_array($name, $declaredFailed, true)) {
                $status = 'failed';
            } elseif ($available) {
                $status = 'planned_not_run';
            }

            if ($requirement === 'required' && $status === 'failed') {
                ++$failedRequired;
            }

            $results[] = [
                'name' => $name,
                'requirement' => $requirement,
                'status' => $status,
                'tolerated' => $requirement === 'optional' && in_array($status, ['skipped_missing', 'failed', 'planned_not_run'], true),
            ];
        }

        return [
            'ok' => $failedRequired === 0,
            'status' => $failedRequired === 0 ? 'TOLERANT_GATE_PLAN_READY' : 'TOLERANT_GATE_REQUIRED_FAILED',
            'results' => $results,
            'resultCount' => count($results),
            'failedRequiredCount' => $failedRequired,
            'nextAction' => $failedRequired === 0 ? 'continue_or_run_missing_gates' : 'return_gate_failure_to_chat',
        ];
    }

    private function csv(mixed $value): array
    {
        if (!is_string($value) || trim($value) === '') {
            return [];
        }

        return array_values(array_filter(array_map('trim', explode(',', $value)), static fn (string $item): bool => $item !== ''));
    }
}
