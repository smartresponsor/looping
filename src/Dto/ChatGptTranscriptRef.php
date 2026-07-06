<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Dto;

final readonly class ChatGptTranscriptRef
{
    public function __construct(
        public string $runId,
        public string $path,
        public string $createdAt,
    ) {
    }

    /**
     * @return array<string, string>
     */
    public function toArray(): array
    {
        return [
            'runId' => $this->runId,
            'path' => $this->path,
            'createdAt' => $this->createdAt,
        ];
    }
}
