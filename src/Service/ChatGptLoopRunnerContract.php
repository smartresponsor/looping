<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopRunnerContract
{
    public function describe(): array
    {
        return [
            'ok' => true,
            'status' => 'RUNNER_CONTRACT_READY',
            'boundary' => [
                'chatgptLoop' => 'plan_route_delegate_resume',
                'runner' => 'dispatch_envelope_to_executor',
                'consoleMcp' => 'execute_tool_and_return_result',
            ],
            'cycle' => [
                'read_stdout.dispatchEnvelope',
                'call_dispatchEnvelope.tool_with_arguments',
                'call_chatgpt_loop_with_dispatch_result',
                'read_stdout.resumeState',
                'repeat_until_stop_policy',
            ],
            'requiredDispatchResultFields' => [
                'dispatch-status',
                'external-task-id',
                'external-chat-id',
                'external-target-id',
            ],
        ];
    }
}
