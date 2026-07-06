<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopFeedbackBuilder
{
    public function build(array $evidence, array $gateRoute, array $tolerantGatePlan): array
    {
        $evidenceStatus = (string) ($evidence['status'] ?? 'EVIDENCE_UNKNOWN');
        $gateStatus = (string) ($tolerantGatePlan['status'] ?? 'TOLERANT_GATE_UNKNOWN');

        if (($evidence['ok'] ?? true) !== true) {
            return $this->feedback(
                false,
                'FEEDBACK_REPO_FACTS_UNSAFE',
                'stop_and_clean_repo',
                'Repository facts are not safe enough to continue.',
                [$evidence['reason'] ?? 'Repository was not measurable safely.']
            );
        }

        if (in_array($evidenceStatus, ['EVIDENCE_INTENT_ONLY', 'EVIDENCE_NOOP_OR_INTENT_ONLY'], true)) {
            return $this->feedback(
                true,
                'FEEDBACK_INTENT_REVIEW_REQUIRED',
                'ask_gateway_intent_review',
                'No repository implementation facts were found.',
                [
                    'Treat this as an intent/no-op response until a commit or diff is observed.',
                    'Send the intent through Ask/Gateway review before allowing another implementation step.',
                ]
            );
        }

        if ($gateStatus === 'TOLERANT_GATE_REQUIRED_FAILED') {
            return $this->feedback(
                false,
                'FEEDBACK_REQUIRED_GATE_FAILED',
                'return_gate_failure_to_chat',
                'Required implementation gate failed.',
                $this->gateMessages($tolerantGatePlan, 'failed')
            );
        }

        if (($gateRoute['status'] ?? null) === 'GATE_ROUTE_READY' && ($tolerantGatePlan['ok'] ?? false) === true) {
            return $this->feedback(
                true,
                'FEEDBACK_IMPLEMENTATION_CAN_CONTINUE',
                'continue_loop',
                'Implementation evidence exists and no required gate failed.',
                $this->gateMessages($tolerantGatePlan, null)
            );
        }

        return $this->feedback(
            true,
            'FEEDBACK_WAIT_OR_REVIEW',
            'wait_or_review',
            'Loop has no blocking feedback, but no continuation approval was produced.',
            [$evidence['reason'] ?? 'No blocking condition detected.']
        );
    }

    private function feedback(bool $ok, string $status, string $nextAction, string $summary, array $messages): array
    {
        return [
            'ok' => $ok,
            'status' => $status,
            'summary' => $summary,
            'messages' => array_values($messages),
            'messageCount' => count($messages),
            'nextAction' => $nextAction,
        ];
    }

    private function gateMessages(array $tolerantGatePlan, ?string $onlyStatus): array
    {
        $results = $tolerantGatePlan['results'] ?? [];
        $results = is_array($results) ? $results : [];
        $messages = [];

        foreach ($results as $result) {
            if (!is_array($result)) {
                continue;
            }

            $status = (string) ($result['status'] ?? 'unknown');
            if ($onlyStatus !== null && $status !== $onlyStatus) {
                continue;
            }

            $messages[] = sprintf('%s: %s (%s)', (string) ($result['name'] ?? 'unknown_gate'), $status, (string) ($result['requirement'] ?? 'optional'));
        }

        return $messages === [] ? ['No gate details were provided.'] : $messages;
    }
}
