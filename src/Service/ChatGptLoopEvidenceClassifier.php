<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopEvidenceClassifier
{
    public function classify(array $snapshot): array
    {
        if (($snapshot['measurable'] ?? false) !== true) {
            return [
                'ok' => true,
                'status' => 'EVIDENCE_INTENT_ONLY',
                'kind' => 'intent_only',
                'confidence' => 'low',
                'nextAction' => 'ask_or_wait_for_repo_facts',
                'reason' => 'No repository facts were supplied for this loop step.',
            ];
        }

        if (($snapshot['dirtyBefore'] ?? null) === true) {
            return [
                'ok' => false,
                'status' => 'EVIDENCE_UNMEASURABLE_DIRTY_BEFORE',
                'kind' => 'unmeasurable_dirty_before',
                'confidence' => 'high',
                'nextAction' => 'clean_or_snapshot_repo_before_retry',
                'reason' => 'Repository was dirty before the step, so new changes cannot be attributed safely.',
            ];
        }

        if (($snapshot['headChanged'] ?? false) === true) {
            return [
                'ok' => true,
                'status' => 'EVIDENCE_COMMIT_CREATED',
                'kind' => 'commit_created',
                'confidence' => 'high',
                'nextAction' => 'run_gates',
                'reason' => 'Repository head changed after the step.',
            ];
        }

        if (($snapshot['diffPresent'] ?? false) === true || ($snapshot['changedFileCount'] ?? 0) > 0 || ($snapshot['dirtyAfter'] ?? null) === true) {
            return [
                'ok' => true,
                'status' => 'EVIDENCE_DIFF_CREATED',
                'kind' => 'diff_created',
                'confidence' => 'medium',
                'nextAction' => 'run_gates_or_request_commit',
                'reason' => 'Repository has working tree changes after the step.',
            ];
        }

        return [
            'ok' => true,
            'status' => 'EVIDENCE_NOOP_OR_INTENT_ONLY',
            'kind' => 'noop_or_intent_only',
            'confidence' => 'medium',
            'nextAction' => 'ask_gateway_intent_review',
            'reason' => 'Repository facts were measurable, but no commit or diff appeared.',
        ];
    }
}
