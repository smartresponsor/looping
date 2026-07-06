<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Entity;

final readonly class ChatGptTask
{
    public function __construct(
        public string $id,
        public string $rawText,
        public ?string $bang,
        public string $body,
    ) {
    }
}
