<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopRoutePlanner
{
    public function plan(array $productPlan, array $budget, ?string $requestedStage): array
    {
        $stages = $productPlan['delegation']['stages'] ?? [];

        if (!is_array($stages) || $stages === []) {
            return ['ok' => false, 'status' => 'ROUTE_NOT_AVAILABLE'];
        }

        $mode = (string) ($budget['mode'] ?? 'single_step');
        $untilRc = ($budget['untilRc'] ?? false) === true;
        $max = $budget['maxIterations'] ?? 1;
        $startStage = $requestedStage ?: (string) $stages[0];

        if (!in_array($startStage, $stages, true)) {
            return [
                'ok' => false,
                'status' => 'ROUTE_START_STAGE_NOT_AVAILABLE',
                'requestedStage' => $startStage,
                'availableStages' => $stages,
            ];
        }

        $startIndex = array_search($startStage, $stages, true);
        $distance = $untilRc ? count($stages) : max(1, (int) $max);
        $allowedStages = array_slice($stages, (int) $startIndex, $distance);

        return [
            'ok' => true,
            'status' => 'ROUTE_PLAN_READY',
            'mode' => $mode,
            'untilRc' => $untilRc,
            'startStage' => $startStage,
            'nextDelegateStage' => $allowedStages[0] ?? null,
            'allowedStages' => $allowedStages,
            'stopPolicy' => $untilRc ? 'stop_when_rc_complete_or_blocked' : 'stop_when_budget_exhausted_or_blocked',
            'remainingBudget' => $untilRc ? null : count($allowedStages),
        ];
    }
}
