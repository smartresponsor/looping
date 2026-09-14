<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopSemanticDecisionRouter
{
    public function route(string $assistantText): array
    {
        $trimmed = trim($assistantText);
        $decoded = $this->decodeJson($trimmed);
        $status = is_array($decoded) && is_string($decoded['status'] ?? null)
            ? strtoupper(trim($decoded['status']))
            : null;

        if ($status === 'DONE') {
            return $this->result('done', true, false, null, $decoded);
        }
        if ($status === 'ACTION_REQUESTED') {
            $action = is_string($decoded['action'] ?? null) ? trim($decoded['action']) : null;
            return $this->result('action_requested', false, true, $action, $decoded);
        }
        if ($status === 'HUMAN_DECISION_REQUIRED') {
            return $this->result('human_decision_required', true, false, null, $decoded);
        }
        if ($status === 'TOOL_CALL_BLOCKED') {
            return $this->result('tool_call_blocked', true, false, null, $decoded);
        }
        if ($status === 'REFUSAL') {
            return $this->result('refusal', true, false, null, $decoded);
        }

        $lower = strtolower($trimmed);
        if (str_contains($lower, 'tool_call_blocked') || str_contains($lower, 'tool call blocked')) {
            return $this->result('tool_call_blocked', true, false, null, $decoded);
        }
        if (preg_match('/\brefus(?:e|al|ed)\b/u', $lower) === 1 || str_contains($lower, "i can't help")) {
            return $this->result('refusal', true, false, null, $decoded);
        }

        return $this->result('continue', false, false, null, $decoded);
    }

    private function result(string $marker, bool $terminalCandidate, bool $actionRequested, ?string $action, ?array $decoded): array
    {
        return [
            'ok' => true,
            'status' => 'SEMANTIC_DECISION_ROUTED',
            'authoritative' => false,
            'marker' => $marker,
            'terminalCandidate' => $terminalCandidate,
            'actionRequested' => $actionRequested,
            'action' => $action,
            'payload' => $decoded,
        ];
    }

    private function decodeJson(string $text): ?array
    {
        if ($text === '' || (!str_starts_with($text, '{') && !str_starts_with($text, '['))) {
            return null;
        }

        try {
            $decoded = json_decode($text, true, 512, JSON_THROW_ON_ERROR);
            return is_array($decoded) ? $decoded : null;
        } catch (\JsonException) {
            return null;
        }
    }
}
