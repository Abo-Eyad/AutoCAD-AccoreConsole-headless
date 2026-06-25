# accoreconsole-headless

**Trustworthy headless verification for AutoCAD / Civil 3D plugin development —
built for an era where an AI agent may have written and run the code.**

This is an [Agent Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview):
a SKILL.md plus reference docs and scripts that teach a coding agent (or a human)
how to execute, verify, and debug AutoCAD / Civil 3D plugins in headless mode
with `accoreconsole.exe` — and, crucially, how to produce *evidence* that a
headless run actually passed instead of merely asserting it did.

## Why this exists

Running plugins headlessly through `accoreconsole.exe` for CI and batch work is
well-trodden ground, with several existing test-runner projects. This skill is
not another test runner. Its focus is the part that breaks silently when a
non-human is in the loop: **verification you can trust.**

- **Crash-marker liveness.** Native access violations (`0xC0000005`) in the
  headless engine cannot be caught by managed code and can leave a
  misleadingly clean exit code. The harness adjudicates by a sentinel printed at
  the end of the script — *marker absent ⇒ fatal crash*, regardless of exit code.
- **Determinism as a gate, not a promise.** A run-twice byte-comparison
  (`fc /b`-equivalent) with justified field normalization, so "reproducible
  output" is demonstrated rather than claimed.
- **An evidence-gated verification checklist.** A box is ticked only when a saved
  log backs it; anything unverified is reported as unverified, not omitted. This
  is the direct countermeasure to an agent fabricating a pass.
- **A headless limitation matrix.** Suppressed commands, the missing graphics
  pipeline, fatal UI instantiation, null ribbon, the non-running autoloader,
  licensing/edition gates — each with its workaround.

## What's inside

```
accoreconsole-headless/
├── SKILL.md                          workflow + crash-marker rule + degradation patterns
├── scripts/
│   ├── run-headless.ps1              harness: auto-detect engine, run .scr, adjudicate by marker
│   ├── headless-test.scr.template    NETLOAD + command slot + crash marker baked in
│   └── verify-deterministic.ps1      run twice, SHA-256 byte-compare, optional field masking
└── references/
    ├── pitfalls.md                   the headless limitation matrix
    └── verification-checklist.md     evidence-gated pass/fail checklist
```

The scripts are version-agnostic: `run-headless.ps1` auto-detects the newest
installed AutoCAD/Civil 3D and accepts `-AcadVersion 2026` to pin one.

## Quick start

```powershell
# 1. Copy the template and fill in the NETLOAD path + your command.
copy scripts\headless-test.scr.template my_smoke.scr

# 2. Run it through the harness; a missing crash marker fails the run.
.\scripts\run-headless.ps1 -ScriptPath .\my_smoke.scr -Marker "AFTER-MARKER"

# 3. If the output claims to be reproducible, prove it.
.\scripts\verify-deterministic.ps1 -ScriptPath .\export.scr -Marker "AFTER-MARKER"
```

Then walk `references/verification-checklist.md` before calling anything passed.

## Intellectual-property note

**This skill is methodology and original tooling only. It contains no Autodesk
source code.** The handful of public API names that appear (e.g. a ribbon null-check)
are documented surface used illustratively.

## License

MIT — see [LICENSE](LICENSE). Fill in the copyright holder before publishing.
