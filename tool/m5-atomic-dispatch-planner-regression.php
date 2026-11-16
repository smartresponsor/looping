<?php

declare(strict_types=1);

use App\Service\ChatGptLoopM5AtomicDispatchPlanner;

require dirname(__DIR__) . '/src/Service/ChatGptLoopM5AtomicDispatchPlanner.php';

$planner = new ChatGptLoopM5AtomicDispatchPlanner();
$closed = $planner->plan(['m5OptInEligible' => false], 'chat_bind', []);
assert($closed['status'] === 'M5_ATOMIC_DISPATCH_CUTOVER_GATE_CLOSED');
assert($closed['runnerExecutionPlan'] === null);
$gate = ['m5OptInEligible' => true];
$base = ['ports' => [9224], 'targetId' => str_repeat('a', 32),
    'chatId' => '6afa61bc-fad0-83ea-8cb9-cdba1ac0a043','taskId' => 'm5-test'];
$bind = $planner->plan($gate, 'chat_bind', $base);
assert($bind['runnerExecutionPlan']['tool'] === 'read_.browser.chatgpt.composer.preflight');
assert($bind['runnerExecutionPlan']['mutation'] === 'read');
assert($bind['runnerExecutionPlan']['arguments']['ports'] === [9224]);
assert($bind['runnerExecutionPlan']['arguments']['expectedTargetId'] === str_repeat('a', 32));
$draft = $planner->plan($gate, 'prompt_draft', $base + ['draftText' => 'hello']);
assert($draft['runnerExecutionPlan']['tool'] === 'write.browser.session.input.draft');
assert($draft['runnerExecutionPlan']['arguments']['confirmDraft'] === true);
$submit = $planner->plan($gate, 'prompt_submit', $base + ['draftHash' => str_repeat('b', 64), 'draftLength' => 5]);
assert($submit['runnerExecutionPlan']['tool'] === 'write.browser.session.submit');
assert($submit['runnerExecutionPlan']['arguments']['confirmSubmit'] === true);
$watch = $planner->plan($gate, 'answer_watch', $base);
assert($watch['runnerExecutionPlan']['tool'] === 'read_.browser.chatgpt.watch.probe');
assert($watch['runnerExecutionPlan']['arguments']['expectedTargetId'] === str_repeat('a', 32));
assert($watch['runnerExecutionPlan']['arguments']['taskClass'] === 'normal_answer');
$settle = $planner->plan($gate, 'answer_settle', $base);
assert($settle['runnerExecutionPlan']['tool'] === 'read_.browser.chatgpt.answer.settle');
foreach ([[9223], [9222,9223], [9223,9224], []] as $ports) {
    $deny = $planner->plan($gate, 'chat_bind', array_replace($base, ['ports'=>$ports]));
    assert($deny['status'] === 'M5_ATOMIC_EXACT_VISIBLE_TARGET_REQUIRED');
}
assert($planner->plan($gate, 'chat_bind', array_replace($base, ['targetId'=>'unsafe']))['ok'] === false);
assert($planner->plan($gate, 'prompt_submit', array_replace($base, ['draftHash'=>null]))['ok'] === false);
assert($planner->plan($gate, 'prompt_submit', array_replace($base, ['draftLength'=>0]))['ok'] === false);
assert($planner->plan($gate, 'prompt_draft', array_replace($base, ['chatId'=>null,'draftText'=>'hello']))['ok'] === false);
assert($planner->plan($gate, 'prompt_draft', [])['ok'] === false);
fwrite(STDOUT, "OK: M5 strict visible target planner regression passed.\n");
