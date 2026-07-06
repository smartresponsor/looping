<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Dto;

final readonly class ChatGptLoopDelegateRequest
{
    public function __construct(public string $stage, public string $component, public string $workspacePath, public string $preset, public bool $confirmationRequired)
    {
    }

    public function toArray(): array
    {
        return [
            'stage' => $this->stage,
            'component' => $this->component,
            'workspacePath' => $this->workspacePath,
            'preset' => $this->preset,
            'confirmationRequired' => $this->confirmationRequired,
        ];
    }
}
