<?php

declare(strict_types=1);

use App\Service\ChatGptLoopAtomicTransportPlan;

require dirname(__DIR__) . '/src/Service/ChatGptLoopAtomicTransportPlan.php';

$plan = (new ChatGptLoopAtomicTransportPlan())->describe();

assert($plan['authoritative'] === false);
assert($plan['legacyEntrypointRequired'] === true);
assert(count($plan['cutoverTarget']) === 7);
assert($plan['cutoverTarget'][0]['stage'] === 'chat_bind');
assert($plan['cutoverTarget'][6]['stage'] === 'message_capture');

fwrite(STDOUT, "OK: atomic transport plan regression passed.\n");
