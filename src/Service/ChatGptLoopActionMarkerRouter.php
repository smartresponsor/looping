<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopActionMarkerRouter
{
    private const CONTINUING = ['continue','next','go','do it','commit','commit and continue','commit and next','fix fail and continue','fix fail and go','fix fail and next','fix fail and commit','fix fail, commit and continue','fix blocker and continue','recheck and continue'];

    public function classify(string $text): array
    {
        $text = trim($text);
        $signals = $this->signals($text);
        $has = static fn(string $name): bool => ($signals[$name] ?? 0) > 0;
        $marker = 'recheck and continue';
        $confidence = 0.66;

        if ($text === '') {
            $confidence = 0.78;
        } elseif ($has('human')) {
            $marker = 'human decision required';
            $confidence = 0.96;
        } elseif ($has('fail') && $has('dirty')) {
            $marker = 'fix fail, commit and continue';
            $confidence = 0.94;
        } elseif ($has('fail')) {
            $marker = 'fix fail and continue';
            $confidence = ($has('commit') || $has('gate')) ? 0.92 : 0.86;
        } elseif ($has('blocker')) {
            $marker = 'fix blocker and continue';
            $confidence = 0.84;
        } elseif ($has('question')) {
            $marker = 'recheck and continue';
            $confidence = 0.74;
        } elseif ($has('done') && $has('green') && $has('clean') && $has('commit')) {
            $marker = 'done';
            $confidence = 0.91;
        } elseif ($has('green') && $has('next')) {
            $marker = 'next';
            $confidence = 0.86;
        } elseif ($has('green')) {
            $marker = 'continue';
            $confidence = 0.80;
        } elseif ($has('commit')) {
            $marker = 'commit and continue';
            $confidence = 0.78;
        }

        return [
            'ok' => true,
            'status' => $marker,
            'marker' => $marker,
            'authoritative' => false,
            'terminalCandidate' => in_array($marker, ['done','human decision required'], true),
            'continue' => in_array($marker, self::CONTINUING, true),
            'replyBackRequired' => !in_array($marker, ['done','human decision required'], true),
            'confidence' => $confidence,
            'signals' => $signals,
        ];
    }

    public function normalize(mixed $value): ?string
    {
        if (!is_string($value)) return null;
        $normalized = preg_replace('/\s+/', ' ', str_replace(['_','.','-'], ' ', strtolower(trim($value))));
        if (!is_string($normalized) || $normalized === '') return null;
        if (in_array($normalized, [...self::CONTINUING,'human decision required','done'], true)) return $normalized;

        return match ($normalized) {
            'green','allow','correct and continue','attention','go next' => 'continue',
            'do fix','red' => 'fix fail and continue',
            'recheck','wait','retry' => 'recheck and continue',
            'complete','completed','task done' => 'done',
            default => null,
        };
    }

    private function signals(string $text): array
    {
        $active = $this->activeIssueText($text);
        return [
            'fail' => $this->count($active, ['/\bfail(?:ed|ing|ure)?\b/iu','/\berror\b/iu','/\binvalid\b/iu','/\bincomplete\b/iu','/\bfailed\s+gate\b/iu','/\bexit\s+code\s*[1-9]\d*\b/iu']),
            'blocker' => $this->count($active, ['/\bblocker\b/iu','/\bblocked\b/iu','/\bcannot\s+proceed\b/iu',"/\\bcan't\\s+proceed\\b/iu"]),
            'gate' => $this->count($text, ['/\bcomposer\s+qa\b/iu','/\bphpunit\b/iu','/\bphpstan\b/iu','/\blint\b/iu','/\btests?\b/iu','/\bgates?\b/iu']),
            'dirty' => $this->count($text, ['/\bdirty\s+(?:worktree|workspace|tree)\b/iu','/\buncommitted\b/iu','/\bnot\s+committed\b/iu','/\bcommit\s+needed\b/iu','/\bneeds?\s+commit\b/iu']),
            'commit' => $this->count($text, ['/\bcommit\s+(?:created|made|done|exists|recorded)\b/iu','/\bcommitted\b/iu','/\bsigned\s+commit\b/iu','/\bcommit:\s*[a-f0-9]{7,40}\b/iu']),
            'clean' => $this->count($text, ['/\bworkspace\s+clean\b/iu','/\bworktree\s+clean\b/iu','/\bgit\s+status\s+clean\b/iu','/\bnothing\s+to\s+commit\b/iu']),
            'green' => $this->count($text, ['/\bpass(?:ed)?\b/iu','/\bgreen\b/iu','/\bok\b/iu','/\bsuccess(?:ful)?\b/iu','/\bgates?\s+green\b/iu']),
            'next' => $this->count($text, ['/\bnext\s+(?:action|step|iteration)\b/iu','/\bcontinue\s+(?:with|to)\b/iu','/\bgo\s+next\b/iu']),
            'question' => $this->count($text, ['/\bwhich\s+(?:option|one)\b/iu','/\bwhat\s+should\b/iu','/\bshould\s+i\b/iu','/\bdo\s+you\s+want\b/iu','/\bplease\s+confirm\b/iu','/\bподтвердите\b/iu']),
            'human' => $this->count($text, ['/\bhuman\s+(?:decision|input|approval)\s+(?:is\s+)?required\b/iu','/\buser\s+(?:decision|input|approval)\s+(?:is\s+)?required\b/iu','/\bproduct\s+decision\s+(?:is\s+)?required\b/iu','/\barchitectural\s+decision\s+(?:is\s+)?required\b/iu','/\brequires?\s+(?:explicit\s+)?approval\b/iu','/\bcannot\s+safely\s+(?:choose|decide|proceed)\b/iu']),
            'done' => $this->count($text, ['/\boriginal\s+(?:specification|task|scope)\s+(?:is\s+)?(?:complete|completed|done)\b/iu','/\ball\s+(?:requested\s+)?(?:scope|work|items)\s+(?:is\s+)?(?:complete|completed|done)\b/iu','/\bno\s+remaining\s+(?:work|items|tasks|action)\b/iu','/\btask\s+(?:is\s+)?(?:complete|completed|done)\b/iu']),
        ];
    }

    private function activeIssueText(string $text): string
    {
        $segments = preg_split('/(?:\r?\n)|(?<=[.!?;])\s+|\s+(?:but|however|yet|though|although|но|однако|зато)\s+/iu', $text) ?: [];
        $resolved = ['/\bno\s+(?:fails?|failures?|errors?)\b/iu','/\bwithout\s+(?:failures?|errors?)\b/iu','/\bnot\s+(?:an?\s+)?(?:fail|failure|error|blocker)\b/iu','/\b(?:fail|failure|error|blocker)\s*[:=]\s*0\b/iu','/\b(?:fail|failure|error|blocker)\b.{0,48}\b(?:fixed|resolved|repaired|closed|cleared|eliminated|gone)\b/iu','/\bfail[- ]closed\b/iu'];
        $active = array_filter(array_map('trim', $segments), static function(string $segment) use ($resolved): bool {
            if ($segment === '') return false;
            foreach ($resolved as $pattern) if (preg_match($pattern, $segment) === 1) return false;
            return true;
        });
        return implode("\n", $active);
    }

    private function count(string $text, array $patterns): int
    {
        $count = 0;
        foreach ($patterns as $pattern) {
            $matched = preg_match_all($pattern, $text, $matches);
            if (is_int($matched) && $matched > 0) $count += $matched;
        }
        return $count;
    }
}
