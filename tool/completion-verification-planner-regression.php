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
], ['composer_validate', 'console.read_.package.composer.script.test'], true);
assert($plan['status'] === 'COMPLETION_VERIFICATION_PLAN_BLOCKED');
assert($plan['readyForM5Execution'] === false);
assert($plan['contracts'][0]['tool'] === 'console.read_.repo.workspace.status');
assert($plan['contracts'][1]['tool'] === 'console.read_.repo.git.branch.status');
assert($plan['contracts'][2]['tool'] === 'console.read_.repo.implementation.run.capture');
assert($plan['contracts'][2]['arguments']['checkNames'][0] === 'composer_validate');
assert(in_array('atomic_git_diff_check_missing', $plan['blockers'], true));
assert(in_array('behavioral_visual_evidence_executor_not_copied', $plan['blockers'], true));

fwrite(STDOUT, "OK: completion verification planner regression passed.\n");
