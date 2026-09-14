<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopCleanupSignalParser
{
    public function parse(string $assistantText): ?bool
    {
        $text = preg_replace('/(?:\r\n|\r|\n)+\z/u', '', $assistantText);
        if (!is_string($text) || $text === '') {
            return null;
        }

        $lastLf = strrpos($text, "\n");
        $lastCr = strrpos($text, "\r");
        $offset = max($lastLf === false ? -1 : $lastLf, $lastCr === false ? -1 : $lastCr);
        $finalLine = substr($text, $offset + 1);

        return match ($finalLine) {
            '{"ready_to_delete":true}' => true,
            '{"ready_to_delete":false}' => false,
            default => null,
        };
    }
}
