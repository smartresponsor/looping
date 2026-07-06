<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Dto;

use App\Enum\ChatGptLoopStatus;

final readonly class ChatGptPromptDispatchResult
{
    public function __construct(
        public bool $ok,
        public ChatGptLoopStatus $status,
        public string $backend,
        public string $message,
    ) {
    }

    /**
     * @return array<string, bool|string>
     */
    public function toArray(): array
    {
        return [
            'ok' => $this->ok,
            'status' => $this->status->value,
            'backend' => $this->backend,
            'message' => $this->message,
        ];
    }
}
