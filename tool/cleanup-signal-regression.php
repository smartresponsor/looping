<?php

declare(strict_types=1);

use App\Service\ChatGptLoopCleanupSignalParser;

require dirname(__DIR__) . '/src/Service/ChatGptLoopCleanupSignalParser.php';

$parser = new ChatGptLoopCleanupSignalParser();

assert($parser->parse("Done.\n{\"ready_to_delete\":true}") === true);
assert($parser->parse("Done.\r\n{\"ready_to_delete\":false}\r\n") === false);
assert($parser->parse("{\"ready_to_delete\":true} trailing") === null);
assert($parser->parse("```json\n{\"ready_to_delete\":true}\n```") === null);
assert($parser->parse("{\"ready_to_delete\": true}") === null);
assert($parser->parse("{\"ready_to_delete\":true,\"reason\":\"done\"}") === null);
assert($parser->parse("Done without signal") === null);
assert($parser->parse("Done.\n{\"ready_to_delete\":true}\n\nSources") === true);
assert($parser->parse("Done.\n{\"ready_to_delete\":false}\nSources") === false);
assert($parser->parse("{\"ready_to_delete\":true}\n1\n2\n3\n4\n5") === null);
assert($parser->parse("{\"ready_to_delete\":true}\nSources\n{\"ready_to_delete\":false}") === null);

fwrite(STDOUT, "OK: cleanup signal parser regression passed.\n");
