<?php

declare(strict_types=1);

use App\Service\ChatGptLoopSemanticDecisionRouter;

require dirname(__DIR__) . '/src/Service/ChatGptLoopSemanticDecisionRouter.php';

$router = new ChatGptLoopSemanticDecisionRouter();

$action = $router->route('{"status":"ACTION_REQUESTED","action":"repo.status.inspect"}');
assert($action['marker'] === 'action_requested');
assert($action['actionRequested'] === true);
assert($action['action'] === 'repo.status.inspect');

$done = $router->route('{"status":"DONE","summary":"ok"}');
assert($done['marker'] === 'done');
assert($done['terminalCandidate'] === true);

$blocked = $router->route('{"status":"TOOL_CALL_BLOCKED"}');
assert($blocked['marker'] === 'tool_call_blocked');

$refusal = $router->route("I can't help with that request.");
assert($refusal['marker'] === 'refusal');

$continue = $router->route('Repository inspection completed; continue with the next safe step.');
assert($continue['marker'] === 'continue');

