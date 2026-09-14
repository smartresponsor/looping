<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopCompletionVerificationContract
{
    public function describe(array $task): array
    {
        $mutationPolicy = ($task['mutation_policy'] ?? null) === 'read_only' ? 'read_only' : 'write_allowed';

        return [
            'ok' => true,
            'status' => 'COMPLETION_VERIFICATION_CONTRACT_READY',
            'authoritative' => false,
            'mutationPolicy' => $mutationPolicy,
            'requirements' => [
                'workspaceIdentity',
                'baselineWorktreeFingerprint',
                'currentWorktreeFingerprint',
                'headVerified',
                'gitDiffCheckPass',
                'readOnlyBaselineMatchWhenRequired',
                'forbiddenCommitPolicyRespected',
                'repositoryDeterministicGates',
                'behavioralApplicabilityEvaluated',
                'reuseExistingRuntimeFirst',
                'behavioralRunnerWhenApplicable',
                'freshVisualEvidenceWhenApplicable',
            ],
            'successRule' => 'verified factual repository state and applicable gates/evidence; textual DONE alone is insufficient',
            'budgetExhaustionIsCompletion' => false,
        ];
    }

    public function evaluateReceipt(array $receipt): array
    {
        $gates = is_array($receipt['gate_results'] ?? null) ? $receipt['gate_results'] : [];
        $failedGates = array_filter($gates, static fn (mixed $result): bool => !is_array($result) || ($result['ok'] ?? false) !== true);
        $applicability = is_array($receipt['applicability'] ?? null) ? $receipt['applicability'] : [];
        $runtime = is_array($receipt['runtime_verification'] ?? null) ? $receipt['runtime_verification'] : [];
        $evidence = is_array($receipt['behavioral_evidence'] ?? null) ? $receipt['behavioral_evidence'] : [];
        $checks = [
            'factsAndGatesVerified' => ($receipt['status'] ?? null) === 'ENGINE_COMPLETION_FACTS_AND_GATES_VERIFIED',
            'worktreeFingerprintPresent' => is_string($receipt['current_worktree_fingerprint'] ?? null) && trim($receipt['current_worktree_fingerprint']) !== '',
            'headPresent' => is_string($receipt['current_head'] ?? null) && preg_match('/^[a-f0-9]{40}$/i', $receipt['current_head']) === 1,
            'gitDiffCheckPass' => ($receipt['git_diff_check'] ?? null) === 'PASS',
            'deterministicGatesPass' => $failedGates === [],
            'runtimePassWhenRequired' => ($runtime['required'] ?? false) !== true || ($runtime['ok'] ?? false) === true,
            'behavioralEvidencePassWhenRequired' => ($applicability['required'] ?? false) !== true || ($evidence['ok'] ?? false) === true,
        ];
        $verified = !in_array(false, $checks, true);

        return [
            'ok' => true,
            'status' => $verified ? 'SHADOW_COMPLETION_VERIFIED' : 'SHADOW_COMPLETION_NOT_VERIFIED',
            'authoritative' => false,
            'verified' => $verified,
            'checks' => $checks,
            'failedGateCount' => count($failedGates),
            'nextAction' => $verified ? 'shadow_allow_verified_done_candidate' : 'shadow_reject_completion_claim',
        ];
    }
}
