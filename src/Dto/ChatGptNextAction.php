<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Dto;

final readonly class ChatGptNextAction
{
    public function __construct(
        public string $code,
        public string $label,
        public string $reason,
    ) {
    }

    /**
     * @return array<string, string>
     */
    public function toArray(): array
    {
        return [
            'code' => $this->code,
            'label' => $this->label,
            'reason' => $this->reason,
        ];
    }
}
