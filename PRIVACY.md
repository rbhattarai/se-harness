# Privacy Policy

**Effective date:** July 16, 2026
**Applies to:** the `se-harness` and `se-harness-copilot` plugins distributed from
this repository (`software-engineering-ai-agents-bootstrap`).

## Summary

These plugins do not collect, store, or transmit any personal data. Period.

## What the plugins do with data

- **Everything runs locally.** The plugins consist of skills, agent definitions,
  commands, hooks, and shell scripts that execute on your machine inside Claude Code
  or GitHub Copilot CLI. They make **no network requests** of their own — no
  telemetry, no analytics, no calls to external servers.
- **Files stay in your project.** Any files the harness creates (`AGENTS.md`,
  `CLAUDE.md`, the `.harness/` directory with project profiles, requirements, and
  memory logs) are written into your own repository on your own machine, under your
  control. Nothing is sent to the plugin author.
- **No accounts, no identifiers.** The plugins require no sign-up, API key, or
  registration, and do not read or fingerprint your identity.

## Data handled by the host tools

The plugins run inside Claude Code (Anthropic) or GitHub Copilot (GitHub/Microsoft).
Prompts, code context, and model traffic are handled by those platforms under their
own privacy policies:

- Anthropic: https://www.anthropic.com/legal/privacy
- GitHub: https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement

This plugin adds no data flows beyond what those host tools already perform.

## Changes

Any change to this policy will be committed to this repository, where its full
history is publicly visible.

## Contact

Questions: Rohan Bhattarai — rohan.bhattarai.dev@gmail.com, or open an issue at
https://github.com/rbhattarai/software-engineering-ai-agents-bootstrap/issues
