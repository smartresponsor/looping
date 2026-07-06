<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Service;

use App\Entity\ChatGptTask;

final class ChatGptTaskBangParser
{
    public function parse(string $rawText): ChatGptTask
    {
        $normalized = trim($rawText);
        $bang = null;
        $body = $normalized;

        if (str_starts_with($normalized, '!')) {
            [$head, $tail] = array_pad(preg_split('/\s+/', $normalized, 2), 2, '');
            $bang = ltrim($head, '!');
            $body = trim($tail);
        }

        return new ChatGptTask(
            id: $this->makeId($normalized),
            rawText: $normalized,
            bang: $bang !== '' ? $bang : null,
            body: $body,
        );
    }

    private function makeId(string $value): string
    {
        return 'task_' . substr(hash('sha256', $value . '|' . date('YmdHis')), 0, 16);
    }
}
