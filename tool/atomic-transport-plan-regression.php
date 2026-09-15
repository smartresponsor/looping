<?php

declare(strict_types=1);

use App\Service\ChatGptLoopAtomicTransportPlan;

require dirname(__DIR__) . '/src/Service/ChatGptLoopAtomicTransportPlan.php';

$plan = (new ChatGptLoopAtomicTransportPlan())->describe();

assert($plan['authoritative'] === false);
assert($plan['legacyEntrypointRequired'] === true);
assert(count($plan['cutoverTarget']) === 7);
assert($plan['cutoverTarget'][0]['stage'] === 'chat_bind');
assert($plan['cutoverTarget'][0]['tool'] === 'console.write.browser.session.open');
assert($plan['cutoverTarget'][0]['bridgeAllowed'] === false);
assert($plan['cutoverTarget'][1]['tool'] === 'console.read_.browser.chatgpt.composer.preflight');
assert($plan['cutoverTarget'][1]['bridgeAllowed'] === true);
assert($plan['cutoverTarget'][2]['tool'] === 'console.write.browser.session.input.draft');
assert($plan['cutoverTarget'][3]['tool'] === 'console.write.browser.session.submit');
assert($plan['cutoverTarget'][6]['stage'] === 'message_capture');
assert(count($plan['bridgeBlockers']) === 3);

fwrite(STDOUT, "OK: atomic transport plan regression passed.\n");
