<?php

declare(strict_types=1);

/*
 * Copyright (c) 2025 Oleksandr Tishchenko / Marketing America Corp
 */

namespace App\State;

use App\Dto\ChatGptNextAction;
use App\Dto\ChatGptPromptDispatchRequest;
use App\Dto\ChatGptPromptDispatchResult;
use App\Dto\ChatGptTranscriptRef;
use App\Entity\ChatGptLifecycleRun;
use App\Entity\ChatGptTask;

final readonly class ChatGptTaskState
{
    public function __construct(
        public ChatGptTask $task,
        public ChatGptLifecycleRun $run,
        public ChatGptPromptDispatchRequest $request,
        public ChatGptPromptDispatchResult $result,
        public ChatGptNextAction $nextAction,
        public ChatGptTranscriptRef $transcript,
    ) {
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'task' => [
                'id' => $this->task->id,
                'rawText' => $this->task->rawText,
                'bang' => $this->task->bang,
                'body' => $this->task->body,
            ],
            'run' => [
                'id' => $this->run->id,
                'taskId' => $this->run->taskId,
                'mode' => $this->run->mode,
                'createdAt' => $this->run->createdAt,
            ],
            'request' => $this->request->toArray(),
            'result' => $this->result->toArray(),
            'nextAction' => $this->nextAction->toArray(),
            'transcript' => $this->transcript->toArray(),
        ];
    }
}
