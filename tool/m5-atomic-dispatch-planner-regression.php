<?php

declare(strict_types=1);

use App\Service\ChatGptLoopM5AtomicDispatchPlanner;

require dirname(__DIR__) . '/src/Service/ChatGptLoopM5AtomicDispatchPlanner.php';

$planner = new ChatGptLoopM5AtomicDispatchPlanner();
$blocked = $planner->plan(['m5OptInEligible' => false], 'chat_bind', []);
assert($blocked['status'] === 'M5_ATOMIC_DISPATCH_CUTOVER_GATE_CLOSED');
assert($blocked['runnerExecutionPlan'] === null);

$gate = ['m5OptInEligible' => true];
$open = $planner->plan($gate, 'chat_bind', []);
assert($open['runnerExecutionPlan']['tool'] === 'write.browser.session.open');
assert($open['runnerExecutionPlan']['authorityMode'] === 'm5_opt_in');
assert($open['runnerExecutionPlan']['arguments']['confirmOpen'] === true);

$draft = $planner->plan($gate, 'prompt_draft', ['targetId' => 'target-1', 'draftText' => 'hello']);
assert($draft['runnerExecutionPlan']['tool'] === 'write.browser.session.input.draft');
assert($draft['runnerExecutionPlan']['arguments']['confirmDraft'] === true);

$submit = $planner->plan($gate, 'prompt_submit', ['targetId' => 'target-1', 'draftHash' => str_repeat('a', 64), 'draftLength' => 5]);
assert($submit['runnerExecutionPlan']['tool'] === 'write.browser.session.submit');
assert($submit['runnerExecutionPlan']['arguments']['confirmSubmit'] === true);

$watch = $planner->plan($gate, 'answer_watch', ['taskId' => 'task-1', 'targetId' => 'target-1', 'chatId' => 'chat-1']);
assert($watch['runnerExecutionPlan']['tool'] === 'read_.browser.chatgpt.watch.probe');
assert($watch['runnerExecutionPlan']['mutation'] === 'read');

$settle = $planner->plan($gate, 'answer_settle', ['taskId' => 'task-1', 'targetId' => 'target-1', 'chatId' => 'chat-1']);
assert($settle['runnerExecutionPlan']['tool'] === 'read_.browser.chatgpt.answer.settle');

$incomplete = $planner->plan($gate, 'prompt_draft', []);
assert($incomplete['status'] === 'M5_ATOMIC_DISPATCH_STATE_INCOMPLETE');

fwrite(STDOUT, "OK: M5 atomic dispatch planner regression passed.\n");
