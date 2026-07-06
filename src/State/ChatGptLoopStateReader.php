<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\State;

use RuntimeException;

final class ChatGptLoopStateReader
{
    public function __construct(
        private readonly string $projectDir,
    ) {
    }

    /**
     * @return array<string, mixed>
     */
    public function read(string $runId): array
    {
        $path = $this->projectDir . '/var/state/' . $runId . '.json';

        if (!is_file($path)) {
            throw new RuntimeException(sprintf('State file not found for run: %s', $runId));
        }

        $decoded = json_decode((string) file_get_contents($path), true);

        if (!is_array($decoded)) {
            throw new RuntimeException(sprintf('State file is invalid for run: %s', $runId));
        }

        return $decoded;
    }
}
