<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Entity;

final readonly class ChatGptLifecycleRun
{
    public function __construct(
        public string $id,
        public string $taskId,
        public string $mode,
        public string $createdAt,
    ) {
    }
}
