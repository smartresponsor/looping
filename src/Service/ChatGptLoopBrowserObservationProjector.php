<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopBrowserObservationProjector
{
    public function project(array $probe, array $step): array
    {
        $probeDecision = is_array($probe['decision'] ?? null) ? $probe['decision'] : [];
        $probeNextAction = $this->firstString(
            $probeDecision['next_action'] ?? null,
            $probeDecision['nextAction'] ?? null,
            $probe['next_action'] ?? null,
            $probe['nextAction'] ?? null,
        );
        $stepNextAction = $this->firstString($step['next_action'] ?? null, $step['nextAction'] ?? null);
        $probeStatus = $this->firstString($probe['status'] ?? null);
        $stepStatus = $this->firstString($step['status'] ?? null);

        $ready = in_array('RUN_STABLE_CAPTURE', [$probeNextAction, $stepNextAction], true)
            || in_array('READY_FOR_STABLE_CAPTURE', [$probeStatus, $stepStatus], true);

        $probePayload = is_array($probe['probe'] ?? null) ? $probe['probe'] : [];
        $messages = is_array($probe['messages'] ?? null)
            ? $probe['messages']
            : (is_array($probePayload['messages'] ?? null) ? $probePayload['messages'] : []);
        $latestAssistant = $probe['latest_assistant'] ?? ($probePayload['latest_assistant'] ?? null);
        $busy = $probePayload['busy'] ?? null;
        $stopMode = $probePayload['composer_stop_control_mode'] ?? null;
        $actionMode = $probePayload['composer_action_mode'] ?? null;

        $quietEmptyBinding = !$ready && (
            in_array($probeStatus, ['LIKELY_STABLE', 'READY_FOR_STABLE_CAPTURE'], true)
            || $stepStatus === 'READY_FOR_STABLE_CAPTURE'
        );

        if ($quietEmptyBinding) {
            $quietEmptyBinding = ($busy === false || $busy === null)
                && ($stopMode === 'not_found' || $stopMode === null)
                && (in_array($actionMode, ['disabled', 'send'], true) || $actionMode === null)
                && count($messages) === 0
                && $latestAssistant === null;
        }

        $state = $ready
            ? 'ready_for_capture'
            : ($quietEmptyBinding ? 'stale_or_empty_binding' : 'wait');

        $nextProbeAfterMs = $this->firstInt(
            $probeDecision['next_probe_after_ms'] ?? null,
            $probeDecision['nextProbeAfterMs'] ?? null,
            3000,
        );

        return [
            'ok' => true,
            'status' => 'SHADOW_BROWSER_OBSERVATION_PROJECTED',
            'authoritative' => false,
            'state' => $state,
            'readyForCapture' => $ready,
            'quietEmptyBinding' => $quietEmptyBinding,
            'probeStatus' => $probeStatus,
            'stepStatus' => $stepStatus,
            'probeNextAction' => $probeNextAction,
            'stepNextAction' => $stepNextAction,
            'nextProbeAfterMs' => min(max(1000, $nextProbeAfterMs), 3000),
            'nextAction' => match ($state) {
                'ready_for_capture' => 'shadow_run_atomic_answer_settle',
                'stale_or_empty_binding' => 'shadow_classify_binding_recovery',
                default => 'shadow_wait_and_probe',
            },
        ];
    }

    private function firstString(mixed ...$values): ?string
    {
        foreach ($values as $value) {
            if (is_string($value) && trim($value) !== '') return trim($value);
        }
        return null;
    }

    private function firstInt(mixed ...$values): int
    {
        foreach ($values as $value) {
            if (is_int($value)) return $value;
            if (is_numeric($value)) return (int) $value;
        }
        return 3000;
    }
}
