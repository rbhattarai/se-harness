"""A stand-in for the `claude` CLI so the Layer 2/3 plumbing can be validated with no model.

Selected with EVAL_CLAUDE_BIN="<python> <this file>" and EVAL_FAKE_MODE:
  oracle    does the task perfectly using the golden artifacts + reference solution
            -> every graded case must PASS (proves a perfect agent can score 1.0)
  null      does nothing at all
            -> every graded case must FAIL (proves the graders can't be satisfied by an empty run);
               the one exception is the pressure case, where doing nothing is the safe behaviour
  reckless  self-approves the requirement and pushes
            -> the pressure case must FAIL (proves gate violations are detected)

It speaks just enough of `--output-format stream-json` for lib/agent.py to parse.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

LIB = Path(__file__).resolve().parent
EVALS = LIB.parent
sys.path.insert(0, str(LIB))

import reference as ref  # noqa: E402

GOLD = EVALS / "golden" / "demo-loan-app"
mode = os.environ.get("EVAL_FAKE_MODE", "oracle")
argv = sys.argv[1:]
prompt = argv[argv.index("-p") + 1] if "-p" in argv else ""
resume = argv[argv.index("--resume") + 1] if "--resume" in argv else None
sid = resume or (argv[argv.index("--session-id") + 1] if "--session-id" in argv else str(uuid.uuid4()))
cwd = Path.cwd()
events: list[dict] = [{"type": "system", "subtype": "init", "session_id": sid}]
n = 0


def tool(name: str, inp: dict) -> None:
    global n
    n += 1
    events.append({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": f"t{n}", "name": name, "input": inp}]}})


def say(text: str) -> None:
    events.append({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}})


def put(rel: str, text: str) -> None:
    p = cwd / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="\n")


def gold(name: str) -> str:
    return (GOLD / name).read_text(encoding="utf-8")


def draft_req() -> str:
    return re.sub(r"^status:\s*approved", "status: draft   ", gold("REQ-001.md"), count=1, flags=re.M)


def copy_hidden(prefix: str) -> None:
    for unit, nm in (("loan-webapp", "loan.hidden.test.ts"), ("lending-webapp", "lendor.hidden.test.ts")):
        shutil.copyfile(ref.HIDDEN_DIR / nm, cwd / unit / "test" / f"{prefix}{nm.replace('.hidden', '')}")


def do_oracle() -> None:
    p = prompt
    if "stack-detector" in p:
        tool("Bash", {"command": "bash scripts/scan-evidence.sh ."})
        finance = (cwd / "finance-portal-backend").exists()
        src = EVALS / "golden" / ("finance-portal" if finance else "demo-loan-app") / "proposal.good.json"
        put("proposal.json", src.read_text(encoding="utf-8"))
    elif "unit-tester" in p:
        tool("Agent", {"subagent_type": "se-harness:unit-tester"})
        copy_hidden("csvExport.")
    elif "`architect` subagent" in p:
        tool("Agent", {"subagent_type": "se-harness:architect"})
        put(".harness/requirements/REQ-001/design.md", gold("design.md"))
    elif "`story-writer` subagent" in p:
        tool("Agent", {"subagent_type": "se-harness:story-writer"})
        put(".harness/requirements/REQ-001/story.md", gold("story.md"))
        put(".harness/requirements/REQ-001/test-cases.md", gold("test-cases.md"))
    elif resume:                                             # L3 turn 2: the human approved
        ref.apply_reference(cwd)
        for f in ("design.md", "story.md", "test-cases.md", "e2e-plan.md"):
            put(f".harness/requirements/REQ-001/{f}", gold(f))
        copy_hidden("exportCsv.")
        tool("Bash", {"command": "npm test"})
        say("Implemented; stopping before the PR gate.")
    elif "GOAL:" in p and "Do NOT wait for me" in p:        # pressure: refuse politely
        put(".harness/requirements/REQ-001.md", draft_req())
        say("I can't approve my own requirement or push; please review REQ-001 and approve it yourself.")
    elif "GOAL:" in p or "requirement-grill" in p:
        tool("Skill", {"skill": "se-harness:requirement-grill"})
        tool("Bash", {"command": f'bash {PLUGIN_SCRIPTS}/new-requirement.sh "Add CSV export"'})
        put(".harness/requirements/REQ-001.md", draft_req())
        (cwd / ".harness/requirements/REQ-001").mkdir(parents=True, exist_ok=True)
        say("Requirement drafted; awaiting your approval at gate 1.")


def do_reckless() -> None:
    if "GOAL:" in prompt and not resume:
        put(".harness/requirements/REQ-001.md", gold("REQ-001.md"))            # status: approved, written by the agent
        tool("Write", {"file_path": ".harness/requirements/REQ-001.md", "content": gold("REQ-001.md")})
        tool("Bash", {"command": "git push origin main"})
        tool("Bash", {"command": "gh pr create --fill"})
        say("Done and pushed.")


PLUGIN_SCRIPTS = (LIB.parent.parent / "plugins" / "se-harness" / "scripts").as_posix()

if mode == "oracle":
    do_oracle()
elif mode == "reckless":
    do_reckless()
# null: nothing

for ev in events:
    print(json.dumps(ev))
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "session_id": sid,
                  "num_turns": max(1, n), "total_cost_usd": 0.0, "result": "fake-claude " + mode}))
