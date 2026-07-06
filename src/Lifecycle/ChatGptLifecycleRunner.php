<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Lifecycle;

final class ChatGptLifecycleRunner
{
    public function __construct(private readonly string $projectDir)
    {
    }
}
