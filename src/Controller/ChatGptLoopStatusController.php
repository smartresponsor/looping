<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Controller;

final class ChatGptLoopStatusController
{
    /**
     * @return array<string, string>
     */
    public function __invoke(): array
    {
        return [
            'service' => 'chatgpt-loop',
            'status' => 'READY_FOR_BACKEND_CONFIGURATION',
        ];
    }
}
