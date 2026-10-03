<?php

declare(strict_types=1);

use App\Service\ChatGptLoopCompletionVerificationPlanner;

require dirname(__DIR__) . '/src/Service/ChatGptLoopCompletionVerificationPlanner.php';

$planner = new ChatGptLoopCompletionVerificationPlanner();

$incomplete = $planner->plan([], []);
assert($incomplete['readyForM5Execution'] === false);
assert($incomplete['blockers'] === ['workspace_or_baseline_head_missing']);

$plan = $planner->plan([
    'workspace_path' => 'D:\\Repo',
    'initial_head' => str_repeat('a', 40),
], ['composer_validate', 'read_.package.composer.script.test'], true);
assert($plan['status'] === 'COMPLETION_VERIFICATION_PLAN_BLOCKED');
assert($plan['readyForM5Execution'] === false);
assert($plan['contracts'][0]['tool'] === 'read_.repo.workspace.status');
assert($plan['contracts'][1]['tool'] === 'read_.repo.git.branch.status');
assert($plan['contracts'][2]['tool'] === 'read_.repo.implementation.run.capture');
assert($plan['contracts'][2]['arguments']['checkNames'][0] === 'composer_validate');
assert($plan['contracts'][3]['tool'] === 'read_.repo.gate.check.run');
assert($plan['contracts'][3]['arguments']['checkName'] === 'git_diff_check');
assert(in_array('git_diff_check_runtime_restart_pending', $plan['blockers'], true));
assert(in_array('behavioral_visual_evidence_executor_not_copied', $plan['blockers'], true));

$ready = $planner->plan([
    'workspace_path' => 'D:\\Repo',
    'initial_head' => str_repeat('a', 40),
], [], false, ['gitDiffCheckRuntimeActive' => true, 'behavioralEvidenceExecutorReady' => false]);
assert($ready['status'] === 'COMPLETION_VERIFICATION_PLAN_READY');
assert($ready['readyForM5Execution'] === true);
assert($ready['blockers'] === []);

fwrite(STDOUT, "OK: completion verification planner regression passed.\n");
