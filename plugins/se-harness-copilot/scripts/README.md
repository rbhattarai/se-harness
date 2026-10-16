Vendor these into each repo the harness manages (commands reference `tools/harness/`). /harness-init does
this for you (Step 0a); by hand it is:

    mkdir -p tools/harness
    cp -R <plugin-dir>/scripts/. tools/harness/
    cp -R <plugin-dir>/templates <plugin-dir>/registry <plugin-dir>/agents <plugin-dir>/plugin.json tools/harness/

Enforcement hooks install at repo level: copy `plugins/se-harness/templates/copilot-hooks.json` from the
framework repo to `.github/hooks/se-harness.json` (see docs/setup-guide-copilot.md 4.7).
