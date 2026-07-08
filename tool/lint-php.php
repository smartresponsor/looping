<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 *
 * Minimal syntax gate: runs `php -l` over every file under src/. This exists specifically
 * because ConsoleMcpCapabilityMap.php once shipped truncated (missing closing braces) and
 * nothing caught it before it reached the working copy - the file that's unconditionally
 * instantiated as the very first step of chatgpt-loop:run, so the whole command was dead
 * on arrival. `php -l` would have caught that in under a second.
 *
 * Usage: php tool/lint-php.php
 * Also wired as: composer lint, and .git/hooks/pre-commit (staged .php files only).
 */

$root = dirname(__DIR__) . '/src';
$errors = [];
$checked = 0;

$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
);

foreach ($iterator as $file) {
    if (!$file->isFile() || $file->getExtension() !== 'php') {
        continue;
    }

    $path = $file->getPathname();
    $checked++;
    $output = [];
    $exitCode = 0;
    exec('php -l ' . escapeshellarg($path) . ' 2>&1', $output, $exitCode);

    if ($exitCode !== 0) {
        $errors[$path] = implode("\n", $output);
    }
}

if ($errors !== []) {
    fwrite(STDERR, sprintf("PHP syntax errors found in %d of %d file(s):\n\n", count($errors), $checked));
    foreach ($errors as $path => $output) {
        fwrite(STDERR, "- {$path}\n{$output}\n\n");
    }
    exit(1);
}

fwrite(STDOUT, sprintf("OK: %d PHP file(s) under src/ parsed cleanly.\n", $checked));
exit(0);
