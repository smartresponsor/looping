<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Dto;

final readonly class ChatGptPromptDispatchRequest
{
    public function __construct(
        public string $runId,
        public string $taskId,
        public string $mode,
        public string $task,
        public ?string $bang,
        public string $createdAt,
    ) {
    }

    /**
     * @return array<string, string|null>
     */
    public function toArray(): array
    {
        return [
            'runId' => $this->runId,
            'taskId' => $this->taskId,
            'mode' => $this->mode,
            'task' => $this->task,
            'bang' => $this->bang,
            'createdAt' => $this->createdAt,
        ];
    }
}
