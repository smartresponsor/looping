<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopCleanupSignalParser
{
    public function parse(string $assistantText): ?bool
    {
        $lines = preg_split('/\r\n|\r|\n/u', $assistantText);
        if (!is_array($lines)) {
            return null;
        }

        $visibleLines = [];
        $insideFence = false;
        foreach ($lines as $line) {
            $trimmed = trim($line);
            if (str_starts_with($trimmed, '```')) {
                $insideFence = !$insideFence;
                continue;
            }
            if (!$insideFence && $trimmed !== '') {
                $visibleLines[] = $trimmed;
            }
        }

        $tail = array_slice($visibleLines, -5);

        $hasTrue = in_array('{"ready_to_delete":true}', $tail, true);
        $hasFalse = in_array('{"ready_to_delete":false}', $tail, true);

        if ($hasTrue === $hasFalse) {
            return null;
        }

        return $hasTrue;
    }
}
