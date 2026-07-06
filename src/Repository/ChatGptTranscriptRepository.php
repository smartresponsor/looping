<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Repository;

use App\Dto\ChatGptPromptDispatchRequest;
use App\Dto\ChatGptPromptDispatchResult;
use App\Dto\ChatGptTranscriptRef;
use RuntimeException;

final class ChatGptTranscriptRepository
{
    public function __construct(
        private readonly string $projectDir,
    ) {
    }

    public function writeReference(
        string $runId,
        string $createdAt,
        ChatGptPromptDispatchRequest $request,
        ChatGptPromptDispatchResult $result,
    ): ChatGptTranscriptRef {
        $dir = $this->projectDir . '/var/transcript';
        $this->ensureDirectory($dir);

        $path = $dir . '/' . $runId . '.json';
        $payload = [
            'runId' => $runId,
            'createdAt' => $createdAt,
            'request' => $request->toArray(),
            'result' => $result->toArray(),
        ];

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

        if (!is_string($json)) {
            throw new RuntimeException('Unable to encode ChatGPT transcript reference.');
        }

        file_put_contents($path, $json . PHP_EOL);

        return new ChatGptTranscriptRef($runId, $path, $createdAt);
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
