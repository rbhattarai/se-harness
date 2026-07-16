# Pull Request

## What does this change?

<!-- Describe the change and why it's needed. Link the related issue if one exists. -->

## Checklist

<!-- See CONTRIBUTING.md for details on each step. -->

- [ ] Changes made in `plugins/se-harness/` (source of truth), **not** hand-edits to the generated `plugins/se-harness-copilot/` or `.github/plugin/marketplace.json`
- [ ] Ran `bash plugins/se-harness/scripts/build-copilot-plugin.sh` and committed the regenerated output (if `plugins/se-harness/` was touched)
- [ ] `claude plugin validate . --strict` and `claude plugin validate ./plugins/se-harness --strict` pass
- [ ] Tested locally with `claude --plugin-dir ./plugins/se-harness` and exercised the changed skill/command/hook
- [ ] No version bumps (maintainers handle releases) and no new network calls (see PRIVACY.md)

## How was it tested?

<!-- Commands run, project used, what you observed. -->
