<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\State;

use RuntimeException;

final class ChatGptLoopStateWriter
{
    public function __construct(
        private readonly string $projectDir,
    ) {
    }

    public function write(ChatGptTaskState $state): string
    {
        $dir = $this->projectDir . '/var/state';
        $this->ensureDirectory($dir);

        $path = $dir . '/' . $state->run->id . '.json';
        $json = json_encode($state->toArray(), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

        if (!is_string($json)) {
            throw new RuntimeException('Unable to encode ChatGPT loop state.');
        }

        file_put_contents($path, $json . PHP_EOL);

        return $path;
    }

    private function ensureDirectory(string $dir): void
    {
        if (is_dir($dir)) {
            return;
        }

        if (!mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new RuntimeException(sprintf('Unable to create directory: %s', $dir));
        }
    }
}
