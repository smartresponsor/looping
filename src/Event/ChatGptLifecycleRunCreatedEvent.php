<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Event;

final readonly class ChatGptLifecycleRunCreatedEvent
{
    public function __construct(
        public string $runId,
        public string $taskId,
        public string $createdAt,
    ) {
    }
}
