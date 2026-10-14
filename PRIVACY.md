# Privacy Policy

**Effective date:** July 16, 2026
**Applies to:** the `se-harness` and `se-harness-copilot` plugins distributed from
this repository (`se-harness`).

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

## Optional observability (opt-in, third party)

`/harness-bootstrap` can offer to set up session tracing with a backend you choose
(Langfuse or Dash0), or you can wire up another one yourself. Nothing is enabled unless
you say yes, and "not yet" / "no thanks" send nothing. When you do opt in:

- The tracing is done by that backend's own plugin (Claude Code) or by Copilot's native
  OpenTelemetry export, **not by se-harness**. se-harness only records your choice
  (provider and host, never a key) in `.harness/profile.yaml`, runs the install after you
  confirm, and prints environment variables for the Copilot path.
- Traces go to the host you configured (your own server or the vendor's cloud) and are
  governed by that backend's privacy policy. Prompt and tool content is off by default for
  Dash0 (`OMIT_IO`) and for the Copilot path (`--capture-content` is opt-in); check the
  setting before enabling it on private code.
- Keys and tokens stay in the OS keychain or the gitignored `.env.harness`, never in the
  profile or any committed file.

## Changes

Any change to this policy will be committed to this repository, where its full
history is publicly visible.

## Contact

Questions: Rohan Bhattarai — rohan.bhattarai.dev@gmail.com, or open an issue at
https://github.com/rbhattarai/se-harness/issues
