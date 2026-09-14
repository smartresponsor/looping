<?php

declare(strict_types=1);

namespace App\Service;

final class ChatGptLoopAtomicTransportPlan
{
    public function describe(): array
    {
        return [
            'ok' => true,
            'status' => 'ATOMIC_TRANSPORT_PLAN_READY',
            'authoritative' => false,
            'legacyEntrypointRequired' => true,
            'cutoverTarget' => [
                ['stage' => 'chat_bind', 'capability' => 'browser.chat.open_or_bind', 'mutation' => 'write'],
                ['stage' => 'composer_preflight', 'capability' => 'browser.composer.preflight', 'mutation' => 'read'],
                ['stage' => 'prompt_draft', 'capability' => 'browser.composer.draft', 'mutation' => 'write'],
                ['stage' => 'prompt_submit', 'capability' => 'browser.composer.submit', 'mutation' => 'write'],
                ['stage' => 'answer_watch', 'capability' => 'browser.answer.observe', 'mutation' => 'read'],
                ['stage' => 'answer_settle', 'capability' => 'browser.answer.settle', 'mutation' => 'read'],
                ['stage' => 'message_capture', 'capability' => 'browser.message.capture', 'mutation' => 'read'],
            ],
            'ownershipRule' => 'ChatGPT Loop owns sequencing, budget, decisions, recovery, checkpoints, and acceptance; Console supplies atomic capabilities only.',
            'currentRule' => 'Do not cut over transport until M4 parity and M5 opt-in acceptance pass.',
        ];
    }
}
