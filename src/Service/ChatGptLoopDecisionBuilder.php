<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopDecisionBuilder
{
    public function build(array $feedback, array $resumeState, array $routePlan, array $loopBudget): array
    {
        $feedbackAction = (string) ($feedback['nextAction'] ?? 'wait_or_review');
        $resumeStatus = (string) ($resumeState['status'] ?? 'RESUME_STATE_UNKNOWN');
        $remainingBudget = $routePlan['remainingBudget'] ?? [];
        $remainingIterations = is_array($remainingBudget) ? (int) ($remainingBudget['maxIterations'] ?? 0) : 0;

        if ($feedbackAction === 'stop_and_clean_repo') {
            return $this->decision(false, 'LOOP_DECISION_CLEAN_REPO_REQUIRED', 'stop', 'Repository must be clean before the loop can attribute implementation facts safely.');
        }

        if ($feedbackAction === 'return_gate_failure_to_chat') {
            return $this->decision(false, 'LOOP_DECISION_RETURN_GATE_FAILURE', 'return_to_chat', 'Required gate failed and must be returned to the implementation chat.');
        }

        if ($feedbackAction === 'ask_gateway_intent_review') {
            return $this->decision(true, 'LOOP_DECISION_ASK_GATEWAY_REVIEW', 'ask_gateway_review', 'No implementation facts were found; intent review is required before another implementation step.');
        }

        if (in_array($resumeStatus, ['RESUME_STATE_BLOCKED', 'RESUME_STATE_FAILED'], true)) {
            return $this->decision(false, 'LOOP_DECISION_RESUME_BLOCKED', 'stop_or_recover', 'Resume state is blocked or failed.');
        }

        if ($remainingIterations <= 0 && (($loopBudget['untilRc'] ?? false) !== true)) {
            return $this->decision(true, 'LOOP_DECISION_BUDGET_EXHAUSTED', 'stop_budget_exhausted', 'Iteration budget is exhausted.');
        }

        if ($feedbackAction === 'continue_loop') {
            return $this->decision(true, 'LOOP_DECISION_CONTINUE', 'continue', 'Implementation can continue to the next loop step.');
        }

        return $this->decision(true, 'LOOP_DECISION_WAIT_OR_REVIEW', 'wait_or_review', 'No blocking decision was produced, but continuation is not explicitly approved.');
    }

    private function decision(bool $ok, string $status, string $action, string $reason): array
    {
        return [
            'ok' => $ok,
            'status' => $status,
            'action' => $action,
            'reason' => $reason,
        ];
    }
}
