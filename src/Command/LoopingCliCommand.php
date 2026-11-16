<?php

declare(strict_types=1);

namespace App\Command;

use App\Service\ChatGptLoopRunnerContract;
use App\Service\ChatGptLoopRunnerDispatcherContract;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * Symfony Console is only the CLI interface; existing Looping PHP services
 * and PowerShell/Node workflow runtime remain authoritative.
 */
final class LoopingCliCommand extends Command
{
    /** @param list<string> $options */
    public function __construct(
        string $name,
        private readonly string $projectDir,
        private readonly array $options = [],
    ) {
        parent::__construct($name);
    }

    /** @return array<string, list<string>> */
    public static function supportedCommands(): array
    {
        return [
            'chatgpt-loop:run' => [
                'task', 'mode', 'plan-only', 'delegate', 'until-rc', 'rc',
                'max-iterations', 'iterations', 'host-result-ok', 'host-task-id',
                'host-chat-id', 'host-target-id',
            ],
            'chatgpt-loop:adopt-current-chat' => [
                'component', 'location', 'current-chat-url',
                'max-auto-iterations', 'plan-only',
            ],
            'chatgpt-loop:contract' => [],
            'chatgpt-loop:dispatcher-contract' => [],
        ];
    }

    protected function configure(): void
    {
        $this->setDescription('Looping CLI compatibility entrypoint (workflow runtime is unchanged).');
        foreach ($this->options as $option) {
            // Legacy CLI accepts both --name and --name=value forms.
            $this->addOption($option, null, InputOption::VALUE_OPTIONAL);
        }
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        // Preserve exact legacy argv serialization, JSON payloads and exit codes.
        // Symfony owns command discovery, help and option validation, not workflow.
        $args = array_slice($_SERVER['argv'] ?? [], 2);

        return match ($this->getName()) {
            'chatgpt-loop:run' => (new ChatGptLoopRunCommand($this->projectDir))->run($args),
            'chatgpt-loop:adopt-current-chat' => (new ChatGptLoopAdoptCurrentChatCommand($this->projectDir))->run($args),
            'chatgpt-loop:contract' => $this->emitContract((new ChatGptLoopRunnerContract())->describe()),
            'chatgpt-loop:dispatcher-contract' => $this->emitContract((new ChatGptLoopRunnerDispatcherContract())->describe()),
            default => Command::FAILURE,
        };
    }

    private function emitContract(array $contract): int
    {
        fwrite(STDOUT, json_encode($contract, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
        return Command::SUCCESS;
    }
}
