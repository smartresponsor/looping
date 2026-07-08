<?php

declare(strict_types=1);

namespace App\Dto;

use InvalidArgumentException;

final readonly class ChatGptLoopBudget
{
    // NOTE: `untilRc` used to mean "no iteration cap at all" (maxIterations stayed null all the
    // way through routePlan/resumeState/nextAction). The actual production loop driver
    // (tool/runner-task-bank-loop.ps1) already enforces its own mandatory -MaxIterations plus a
    // wall-clock timeout, so this was not an exploitable infinite loop in the live path - but this
    // PHP layer is meant to be the authoritative model of the budget, and it should never itself
    // describe an unbounded loop as "no limit". Give until_rc a real, generous but finite default
    // cap unless the caller explicitly overrides it with --max-iterations.
    public const int DEFAULT_UNTIL_RC_MAX_ITERATIONS = 50;

    public function __construct(public string $mode, public ?int $maxIterations, public bool $untilRc)
    {
    }

    public static function fromOptions(array $options): self
    {
        $untilRc = ($options['until-rc'] ?? '0') === '1' || ($options['rc'] ?? '0') === '1';
        $rawMax = $options['max-iterations'] ?? $options['iterations'] ?? null;

        if ($untilRc) {
            if ($rawMax === null || $rawMax === '') {
                return new self('until_rc', self::DEFAULT_UNTIL_RC_MAX_ITERATIONS, true);
            }

            if (!ctype_digit((string) $rawMax)) {
                throw new InvalidArgumentException('The iteration limit must be a positive integer or --until-rc=1.');
            }

            $max = (int) $rawMax;

            if ($max < 1) {
                throw new InvalidArgumentException('The iteration limit must be greater than zero.');
            }

            return new self('until_rc', $max, true);
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
