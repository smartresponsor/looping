<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopReplyBackPolicy
{
    public function build(string $marker, array $task): array
    {
        $readOnly = ($task['mutation_policy'] ?? null) === 'read_only';
        $commitForbidden = ($task['git_commit_policy'] ?? null) === 'forbidden';
        $stageForbidden = ($task['git_stage_policy'] ?? null) === 'forbidden';
        $pushForbidden = ($task['git_push_policy'] ?? null) === 'forbidden';
        $marker = $commitForbidden ? $this->stripCommitMarker($marker) : $marker;
        $rawNext = is_string($task['decision_next_action'] ?? null) && trim($task['decision_next_action']) !== ''
            ? trim($task['decision_next_action'])
            : 'Recheck the latest executor report, choose the next bounded action, and continue without asking for approval.';
        $next = $readOnly
            ? 'Continue with read-only verification only. Do not modify, stage, commit, reset, clean, delete, rename, or generate repository files.'
            : $this->sanitize($rawNext, $marker, $commitForbidden, $stageForbidden, $pushForbidden);

        $lines = ["Decision: {$marker}.", '', $next];
        if (is_string($task['workspace_path'] ?? null) && trim($task['workspace_path']) !== '') {
            $lines[] = '';
            $lines[] = 'Capability guard: repository writes are confined to ' . trim($task['workspace_path']) . '. Do not modify sibling repositories.';
        }
        if ($commitForbidden) $lines[] = 'Git commit is FORBIDDEN for this task.';
        if ($stageForbidden) $lines[] = 'Git stage is FORBIDDEN for this task.';
        if ($pushForbidden) $lines[] = 'Git push is FORBIDDEN for this task.';

        return [
            'ok' => true,
            'status' => 'SHADOW_REPLY_BACK_POLICY_PROJECTED',
            'authoritative' => false,
            'marker' => $marker,
            'readOnly' => $readOnly,
            'commitForbidden' => $commitForbidden,
            'stageForbidden' => $stageForbidden,
            'pushForbidden' => $pushForbidden,
            'text' => implode("\n", $lines),
        ];
    }

    private function stripCommitMarker(string $marker): string
    {
        return match ($marker) {
            'commit', 'commit and continue' => 'continue',
            'commit and next' => 'next',
            'fix fail and commit', 'fix fail, commit and continue' => 'fix fail and continue',
            default => $marker,
        };
    }

    private function sanitize(string $next, string $marker, bool $commitForbidden, bool $stageForbidden, bool $pushForbidden): string
    {
        $conflict = ($commitForbidden && preg_match('/\bcommit(?:ted|ting)?\b/i', $next) === 1)
            || ($stageForbidden && preg_match('/\bstag(?:e|ed|ing)\b/i', $next) === 1)
            || ($pushForbidden && preg_match('/\bpush(?:ed|ing)?\b/i', $next) === 1);
        if (!$conflict) return $next;

        if (in_array($marker, ['fix fail and continue','fix fail and go','fix fail and next'], true)) {
            return 'Fix the reported failure only within the authorized workspace, rerun relevant verification until green, and continue while safe in-scope work remains.';
        }
        if ($marker === 'fix blocker and continue') {
            return 'Fix the reported blocker only within the authorized workspace, verify the affected path, and continue while safe in-scope work remains.';
        }

        return 'Continue the next bounded action only within the authorized workspace while preserving all Git-operation restrictions.';
    }
}
