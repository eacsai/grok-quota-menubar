# Experiment results

Not a research/training project. There are no published metrics,
datasets, or comparison arms.

Verified on the source Mac (2026-08-19):

- `scripts/test.sh` → `all tests passed`
- `scripts/build.sh` produces `dist/GrokQuota.app`
- After `scripts/install.sh`, LaunchAgent
  `ai.xai.grok-quota-menubar` ran; `--once --json` returned a weekly
  GrokBuild snapshot (`ok: true`, no token fields).

Do not treat a missing live `auth.json` on a new machine as a test
failure.
