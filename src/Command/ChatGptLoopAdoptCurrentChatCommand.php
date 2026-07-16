<?php

declare(strict_types=1);

namespace App\Command;

use InvalidArgumentException;
use RuntimeException;
use Throwable;

final class ChatGptLoopAdoptCurrentChatCommand
{
    public function __construct(private readonly string $projectDir)
    {
    }

    public function run(array $args): int
    {
        try {
            $options = $this->parseOptions($args);
            $componentName = trim((string) ($options['component'] ?? ''));
            $existingLocation = trim((string) ($options['location'] ?? $options['current-chat-url'] ?? ''));
            $maxAutoIterations = $this->parseIterationBudget((string) ($options['max-auto-iterations'] ?? '3'));
            $planOnly = $this->parseBoolean((string) ($options['plan-only'] ?? '0'));

            if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$/', $componentName)) {
                throw new InvalidArgumentException('The --component option is required and must be a valid component name.');
            }

            if ($existingLocation === '') {
                throw new InvalidArgumentException('The --location option is required.');
            }
            $chatId = $this->extractChatId($existingLocation);
            $runnerPath = $this->projectDir . '/tool/runner-adopt-current-chat.ps1';
            if (!is_file($runnerPath)) {
                throw new RuntimeException('Adoption runner not found: ' . $runnerPath);
            }

            $contract = [
                'componentName' => $componentName,
                'existingLocation' => $existingLocation,
                'chatId' => $chatId,
                'maxAutoIterations' => $maxAutoIterations,
                'runnerPath' => $runnerPath,
                'ownsCurrentChatResolution' => false,
                'resolverOwner' => 'console-mcp',
                'usesExistingLocationResolver' => true,
            ];

            if ($planOnly) {
                return $this->printJson([
                    'ok' => true,
                    'status' => 'ADOPT_CURRENT_CHAT_PLAN_READY',
                    'contract' => $contract,
                    'executed' => false,
                ], STDOUT, 0);
            }

            $result = $this->runPowerShell($runnerPath, $componentName, $existingLocation, $maxAutoIterations);
            $decoded = json_decode($result['stdout'], true);

            return $this->printJson([
                'ok' => $result['exitCode'] === 0,
                'status' => $result['exitCode'] === 0 ? 'ADOPT_CURRENT_CHAT_EXECUTED' : 'ADOPT_CURRENT_CHAT_FAILED',
                'contract' => $contract,
                'executed' => true,
                'exitCode' => $result['exitCode'],
                'result' => is_array($decoded) ? $decoded : null,
                'stdout' => is_array($decoded) ? null : $result['stdout'],
                'stderr' => $result['stderr'] !== '' ? $result['stderr'] : null,
            ], $result['exitCode'] === 0 ? STDOUT : STDERR, $result['exitCode'] === 0 ? 0 : 1);
        } catch (Throwable $exception) {
            return $this->printJson([
                'ok' => false,
                'status' => 'ADOPT_CURRENT_CHAT_REJECTED',
                'error' => $exception->getMessage(),
            ], STDERR, 1);
        }
    }

    private function extractChatId(string $reference): ?string
    {
        if (preg_match('/^[0-9a-fA-F-]{36}$/', $reference) === 1) {
            return strtolower($reference);
        }

        $parts = parse_url($reference);
        if (!is_array($parts) || !isset($parts['scheme'])) {
            return null;
        }
        if (($parts['scheme'] ?? null) !== 'https') {
            throw new InvalidArgumentException('Chat URL must be a valid HTTPS URL.');
        }

        $host = strtolower((string) ($parts['host'] ?? ''));
        if (!in_array($host, ['chatgpt.com', 'chat.openai.com'], true)) {
            throw new InvalidArgumentException('Chat URL must use chatgpt.com or chat.openai.com.');
        }

        $path = (string) ($parts['path'] ?? '');
        if (preg_match('#^/(?:c|chat)/([0-9a-fA-F-]{36})/?$#', $path, $matches) !== 1) {
            throw new InvalidArgumentException('Chat URL does not contain a supported conversation UUID.');
        }

        return strtolower($matches[1]);
    }

    private function parseIterationBudget(string $value): int
    {
        if (!ctype_digit($value)) {
            throw new InvalidArgumentException('The --max-auto-iterations option must be an integer from 1 to 100.');
        }

        $iterations = (int) $value;
        if ($iterations < 1 || $iterations > 100) {
            throw new InvalidArgumentException('The --max-auto-iterations option must be between 1 and 100.');
        }

        return $iterations;
    }

    private function parseBoolean(string $value): bool
    {
        return in_array(strtolower($value), ['1', 'true', 'yes', 'on'], true);
    }

    private function runPowerShell(string $runnerPath, string $componentName, string $existingLocation, int $iterations): array
    {
        $command = [
            'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runnerPath,
            '-ComponentName', $componentName,
            '-ExistingLocation', $existingLocation,
            '-MaxIterations', (string) $iterations,
        ];
        $pipes = [];
        $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, $this->projectDir);
        if (!is_resource($process)) {
            throw new RuntimeException('Unable to start the adoption runner.');
        }

        $stdout = stream_get_contents($pipes[1]);
        $stderr = stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        $exitCode = proc_close($process);

        return ['exitCode' => $exitCode, 'stdout' => trim((string) $stdout), 'stderr' => trim((string) $stderr)];
    }

    private function parseOptions(array $args): array
    {
        $options = [];
        foreach ($args as $arg) {
            if (str_starts_with($arg, '--')) {
                [$name, $value] = array_pad(explode('=', substr($arg, 2), 2), 2, '1');
                $options[$name] = $value;
            }
        }

        return $options;
    }

    private function printJson(array $payload, mixed $stream, int $code): int
    {
        fwrite($stream, json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);

        return $code;
    }
}
