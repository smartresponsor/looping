<?php

declare(strict_types=1);

use App\Service\ChatGptLoopActionMarkerRouter;

require dirname(__DIR__) . '/src/Service/ChatGptLoopActionMarkerRouter.php';

$router = new ChatGptLoopActionMarkerRouter();

$failDirty = $router->classify('PHPUnit failed. Worktree is dirty and needs commit.');
assert($failDirty['marker'] === 'fix fail, commit and continue');

$resolved = $router->classify('Previous failure fixed. PHPUnit passed and workspace clean. Continue with the next step.');
assert($resolved['marker'] === 'next');
assert($resolved['signals']['fail'] === 0);

$human = $router->classify('An architectural decision is required before proceeding.');
assert($human['marker'] === 'human decision required');

$done = $router->classify('Task complete. PHPUnit passed. Workspace clean. Signed commit created.');
assert($done['marker'] === 'done');
assert($done['terminalCandidate'] === true);

$commit = $router->classify('Signed commit created.');
assert($commit['marker'] === 'commit and continue');

$unknown = $router->classify('Inspected repository state.');
assert($unknown['marker'] === 'recheck and continue');

assert($router->normalize('COMPLETE') === 'done');
assert($router->normalize('go_next') === 'continue');
assert($router->normalize('red') === 'fix fail and continue');

fwrite(STDOUT, "OK: action marker router regression passed.\n");
