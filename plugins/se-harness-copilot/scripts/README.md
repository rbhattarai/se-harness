Vendor these into each repo the harness manages (commands reference `tools/harness/`):

    mkdir -p tools/harness && cp <plugin-dir>/scripts/*.sh tools/harness/

Enforcement hooks install at repo level: copy `plugins/se-harness/templates/copilot-hooks.json` from the
framework repo to `.github/hooks/se-harness.json` (see docs/setup-guide-copilot.md 4.7).
