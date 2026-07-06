<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\Enum;

enum ChatGptLoopStatus: string
{
    case Accepted = 'ACCEPTED';
    case BackendNotConfigured = 'BACKEND_NOT_CONFIGURED';
    case StateWritten = 'STATE_WRITTEN';
    case Failed = 'FAILED';
}
