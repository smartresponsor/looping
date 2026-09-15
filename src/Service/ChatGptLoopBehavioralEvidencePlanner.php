<?php
declare(strict_types=1);
namespace App\Service;
final class ChatGptLoopBehavioralEvidencePlanner
{
    public function applicability(array $changedFiles, array $discoveredRunners = []): array
    {
        $changed = array_values(array_unique(array_map(
            static fn (mixed $file): string => str_replace('\\', '/', trim((string) $file)),
            array_filter($changedFiles, static fn (mixed $file): bool => is_string($file) && trim($file) !== ''),
        )));
        sort($changed);
        $relevant = array_values(array_filter($changed, fn (string $file): bool => !$this->matchesAny($file, [
            '#(^|/)docs?/#i', '#(^|/)var/#i', '#(^|/)vendor/#i', '#(^|/)node_modules/#i',
            '#(^|/)tests?/Fixtures/#i', '#(^|/)README(?:\.|$)#i',
        ])));
        $web = array_values(array_filter($relevant, fn (string $file): bool => $this->matchesAny($file, [
            '#(^|/)templates/#i', '#(^|/)assets/#i', '#(^|/)public/#i', '#(^|/)src/Controller/#i',
            '#(^|/)src/Form/#i', '#(^|/)(?:frontend|ui|browser|stimulus)/#i', '#\.(?:twig|html?|css|scss|sass|jsx|tsx)$#i',
        ])));
        $android = array_values(array_filter($relevant, fn (string $file): bool => $this->matchesAny($file, [
            '#(^|/)client/android/#i', '#(^|/)android/#i', '#\.kt$#i',
        ])));
        $ios = array_values(array_filter($relevant, fn (string $file): bool => $this->matchesAny($file, [
            '#(^|/)client/ios/#i', '#(^|/)ios/#i', '#\.swift$#i',
        ])));
        $platforms = [];
        if ($web !== []) $platforms[] = 'web';
        if ($android !== []) $platforms[] = 'android';
        if ($ios !== []) $platforms[] = 'ios';
        $matched = array_values(array_unique([...$web, ...$android, ...$ios]));
        sort($matched);
        return [
            'ok' => true,
            'status' => 'SHADOW_BEHAVIORAL_APPLICABILITY_PROJECTED',
            'authoritative' => false,
            'required' => $matched !== [],
            'surface' => $platforms === [] ? 'none' : (count($platforms) > 1 ? 'mixed' : ($platforms[0] === 'web' ? 'web_ui' : 'mobile_ui')),
            'changedFiles' => $changed,
            'matchedFiles' => $matched,
            'expectedPlatforms' => $platforms,
            'discoveredRunners' => array_values(array_unique(array_filter($discoveredRunners, 'is_string'))),
        ];
    }
    public function evaluate(array $applicability, array $runtimeEvidence, array $visualEvidence, string $taskCreatedAt): array
    {
        if (($applicability['required'] ?? false) !== true) {
            return ['ok' => true, 'status' => 'SHADOW_BEHAVIORAL_NOT_APPLICABLE', 'authoritative' => false, 'verified' => true, 'blockers' => []];
        }
        $blockers = [];
        if (($applicability['discoveredRunners'] ?? []) === []) $blockers[] = 'behavioral_runner_missing';
        if (($runtimeEvidence['required'] ?? false) === true && ($runtimeEvidence['ok'] ?? false) !== true) $blockers[] = 'reuse_first_runtime_not_ready';
        $capturedAt = is_string($visualEvidence['captured_at'] ?? null) ? strtotime($visualEvidence['captured_at']) : false;
        $createdAt = strtotime($taskCreatedAt);
        if (($visualEvidence['schema'] ?? null) !== 'visual-artifact-run-v1') $blockers[] = 'visual_artifact_schema_invalid';
        if (!in_array($visualEvidence['producer'] ?? null, ['localhost-inspect', 'playwright', 'panther', 'mobile-ui'], true)) $blockers[] = 'visual_artifact_producer_unverified';
        if ($capturedAt === false || $createdAt === false || $capturedAt < $createdAt) $blockers[] = 'visual_artifact_not_fresh_for_task';
        $expectedPlatforms = is_array($applicability['expectedPlatforms'] ?? null) ? $applicability['expectedPlatforms'] : [];
        $platform = $visualEvidence['platform'] ?? null;
        if ($expectedPlatforms !== [] && (!is_string($platform) || !in_array($platform, $expectedPlatforms, true))) $blockers[] = 'visual_artifact_platform_mismatch';
        $blockers = array_values(array_unique($blockers));
        return [
            'ok' => true,
            'status' => $blockers === [] ? 'SHADOW_BEHAVIORAL_EVIDENCE_VERIFIED' : 'SHADOW_BEHAVIORAL_EVIDENCE_BLOCKED',
            'authoritative' => false,
            'verified' => $blockers === [],
            'blockers' => $blockers,
            'runtimePolicy' => 'reuse_existing_first',
        ];
    }
    private function matchesAny(string $value, array $patterns): bool
    {
        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $value) === 1) return true;
        }
        return false;
    }
}
