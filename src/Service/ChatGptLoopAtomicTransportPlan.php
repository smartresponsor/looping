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
                ['stage' => 'chat_bind', 'tool' => 'console.write.browser.session.open', 'mutation' => 'write', 'bridgeAllowed' => false],
                ['stage' => 'composer_preflight', 'tool' => 'console.read_.browser.chatgpt.composer.preflight', 'mutation' => 'read', 'bridgeAllowed' => true],
                ['stage' => 'prompt_draft', 'tool' => 'console.write.browser.session.input.draft', 'mutation' => 'write', 'bridgeAllowed' => false],
                ['stage' => 'prompt_submit', 'tool' => 'console.write.browser.session.submit', 'mutation' => 'write', 'bridgeAllowed' => false],
                ['stage' => 'answer_watch', 'tool' => 'console.read_.browser.chatgpt.watch.probe', 'mutation' => 'read', 'bridgeAllowed' => true],
                ['stage' => 'answer_settle', 'tool' => 'console.read_.browser.chatgpt.answer.settle', 'mutation' => 'read', 'bridgeAllowed' => true],
                ['stage' => 'message_capture', 'tool' => 'console.read_.browser.chatgpt.message.capture', 'mutation' => 'read', 'bridgeAllowed' => true],
            ],
            'bridgeBlockers' => [
                'console.write.browser.session.open',
                'console.write.browser.session.input.draft',
                'console.write.browser.session.submit',
            ],
            'ownershipRule' => 'ChatGPT Loop owns sequencing, budget, decisions, recovery, checkpoints, and acceptance; Console supplies atomic capabilities only.',
            'currentRule' => 'Do not cut over transport until M4 parity and M5 opt-in acceptance pass.',
        ];
    }
}
