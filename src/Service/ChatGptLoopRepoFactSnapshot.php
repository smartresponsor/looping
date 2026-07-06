<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopRepoFactSnapshot
{
    public function fromOptions(array $options): array
    {
        $beforeHead = $this->stringOrNull($options['repo-before-head'] ?? null);
        $afterHead = $this->stringOrNull($options['repo-after-head'] ?? null);
        $dirtyBefore = $this->boolOrNull($options['repo-dirty-before'] ?? null);
        $dirtyAfter = $this->boolOrNull($options['repo-dirty-after'] ?? null);
        $diffStat = $this->stringOrNull($options['repo-diff-stat'] ?? null);
        $changedFiles = $this->csv($options['repo-changed-files'] ?? null);

        return [
            'ok' => true,
            'status' => 'REPO_FACT_SNAPSHOT_READY',
            'beforeHead' => $beforeHead,
            'afterHead' => $afterHead,
            'dirtyBefore' => $dirtyBefore,
            'dirtyAfter' => $dirtyAfter,
            'headChanged' => $beforeHead !== null && $afterHead !== null && $beforeHead !== $afterHead,
            'diffPresent' => $diffStat !== null && trim($diffStat) !== '',
            'changedFiles' => $changedFiles,
            'changedFileCount' => count($changedFiles),
            'measurable' => $beforeHead !== null || $afterHead !== null || $dirtyBefore !== null || $dirtyAfter !== null || $diffStat !== null || $changedFiles !== [],
        ];
    }

    private function stringOrNull(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : $trimmed;
    }

    private function boolOrNull(mixed $value): ?bool
    {
        if (!is_string($value)) {
            return null;
        }

        return match (strtolower(trim($value))) {
            '1', 'true', 'yes', 'dirty' => true,
            '0', 'false', 'no', 'clean' => false,
            default => null,
        };
    }

    private function csv(mixed $value): array
    {
        if (!is_string($value) || trim($value) === '') {
            return [];
        }

        return array_values(array_filter(array_map('trim', explode(',', $value)), static fn (string $item): bool => $item !== ''));
    }
}
