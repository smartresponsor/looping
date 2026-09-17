<?php

declare(strict_types=1);

$path = __DIR__ . '/runner-task-bank-loop.ps1';
$source = file_get_contents($path);

if ($source === false) {
    fwrite(STDERR, "unable to read runner-task-bank-loop.ps1\n");
    exit(1);
}

$safe = "\$ReadyToDeleteComplete = ((Get-OptionalProperty -InputObject \$Task -Name 'readyToDelete') -eq \$true)";
$unsafe = "\$ReadyToDeleteComplete = (\$Task.readyToDelete -eq \$true)";

assert(str_contains($source, $safe));
assert(!str_contains($source, $unsafe));
echo "ready-to-delete optional regression passed\n";
