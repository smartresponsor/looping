<?php

declare(strict_types=1);

namespace App\Dto;

use InvalidArgumentException;

final readonly class ChatGptLoopBudget
{
    public function __construct(public string $mode, public ?int $maxIterations, public bool $untilRc)
    {
    }

    public static function fromOptions(array $options): self
    {
        $untilRc = ($options['until-rc'] ?? '0') === '1' || ($options['rc'] ?? '0') === '1';
        $rawMax = $options['max-iterations'] ?? $options['iterations'] ?? null;

        if ($untilRc) {
            return new self('until_rc', null, true);
        }

        if ($rawMax === null || $rawMax === '') {
            return new self('single_step', 1, false);
        }

        if (!ctype_digit((string) $rawMax)) {
            throw new InvalidArgumentException('The iteration limit must be a positive integer or --until-rc=1.');
        }

        $max = (int) $rawMax;

        if ($max < 1) {
            throw new InvalidArgumentException('The iteration limit must be greater than zero.');
        }

        return new self($max === 1 ? 'single_step' : 'bounded', $max, false);
    }

    public function toArray(): array
    {
        return ['mode' => $this->mode, 'maxIterations' => $this->maxIterations, 'untilRc' => $this->untilRc];
    }
}
