<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 *
 * Removed as dead code: never called from bin/console or ChatGptLoopRunCommand, which parses
 * the "!bang" prefix and generates taskId inline instead (and does so slightly differently -
 * this class hashed with local server time via date(), the live inline code uses gmdate('c'),
 * i.e. UTC). Kept as an empty namespace file rather than deleted outright (no delete tool
 * available), so App\Entity\ChatGptTask (still used by App\State\ChatGptTaskState) is
 * unaffected. If this parser is ever wired back in, prefer aligning it with the inline
 * UTC-based id generation rather than reintroducing the local-timezone variant.
 */

namespace App\Service;
