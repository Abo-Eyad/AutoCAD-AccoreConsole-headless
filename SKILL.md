---
name: accoreconsole-headless
description: Execute, verify, and debug AutoCAD and Civil 3D plugins in headless mode with accoreconsole.exe. Use this skill whenever the user mentions accoreconsole, headless AutoCAD or Civil 3D, .scr scripts, NETLOAD testing, automated or CI regression testing of a plugin, determinism or byte-for-byte verification of plugin output, or debugging failures that only appear headlessly such as access violations, suppressed commands, a null Ribbon, or PaletteSet crashes. Also use whenever an agent must produce trustworthy evidence that a headless run actually passed instead of merely asserting success. Covers the crash-marker pattern, the headless limitation matrix, a parameterized PowerShell harness, a .scr template, a determinism checker, and a pre-flight verification checklist that prevents fabricated pass claims.
---

# Headless AutoCAD / Civil 3D Testing with `accoreconsole.exe`

`accoreconsole.exe` is the headless core engine that ships with AutoCAD and
Civil 3D. It loads DWGs, runs commands, and executes managed (.NET) plugins
**without a GUI, display pipeline, or full application host**. That makes it the
right tool for automated regression testing, CI, and deterministic verification
of plugins — but it behaves differently enough from the full product that naive
tests give false results, and certain operations crash the engine outright.

This skill exists for one reason above all: **a headless run only counts as
passed when there is real, captured evidence that it passed.** Native crashes in
this engine cannot be caught by managed code, so "the command returned" is not
proof of anything. Treat every claim of success as something to be demonstrated,
not narrated.

## The placeholder convention

Engine paths are version-specific. Throughout this skill, `ACAD_VERSION` stands
for the installed release year (e.g. `2026`, `2027`) and the engine lives at:

```
C:\Program Files\Autodesk\AutoCAD ACAD_VERSION\accoreconsole.exe
```

(Civil 3D installs *inside* the AutoCAD folder, so the path is the same.) The
bundled `run-headless.ps1` auto-detects the newest installed version; pass
`-AcadVersion 2026` to pin a specific one. Never hard-code a year in a script you
intend to reuse across releases.

## Core workflow

For any headless task, follow this sequence. Do not skip the evidence steps.

1. **Read `references/pitfalls.md` first** if the task touches UI, rendering,
   ribbons, content publishing, the autoloader, or any crash. It is the matrix of
   what is suppressed or fatal headlessly and how to degrade gracefully. Reaching
   for these by memory is how false passes happen.
2. **Write the `.scr` from the template** (`scripts/headless-test.scr.template`).
   Every test script must explicitly `NETLOAD` the plugin assembly (the GUI
   autoloader does **not** run headlessly) and must end with the crash marker.
3. **Run it through the harness** (`scripts/run-headless.ps1`), never by hand-
   rolling the command line. The harness captures stdout/stderr, enforces a
   timeout, and adjudicates the marker.
4. **Adjudicate by evidence, not by exit code alone.** A missing crash marker
   means a fatal native crash *even if the process exit code looks clean*. See
   "The crash-marker pattern" below.
5. **For any output that must be reproducible**, prove it with
   `scripts/verify-deterministic.ps1` (runs twice, byte-compares). Do not assert
   determinism; demonstrate it.
6. **Walk `references/verification-checklist.md` before reporting a pass.** If you
   cannot tick a box with captured evidence, the box is not ticked.

## The crash-marker pattern (non-negotiable)

Instantiating GUI objects, touching the graphics system, or hitting an
unsupported native path can raise an **uncatchable** access violation
(`0xC0000005`). Managed `try/catch` will not save you — the process dies. So you
cannot rely on a returned value or a thrown-and-caught exception to know the run
survived.

The fix is a sentinel printed at the very end of the script:

```lisp
(princ "\nAFTER-MARKER\n")
```

If the harness sees `AFTER-MARKER` in stdout, the script ran to completion. If it
does **not** see it, the engine died partway through — that is a hard crash, and
the test FAILS regardless of what else was printed. `run-headless.ps1` checks for
this automatically and treats a missing marker as a fatal failure.

## Determinism proving

When a feature claims to produce stable output (snapshots, JSON reports,
exported catalogs), reproducibility is a testable property, not a promise. Run
the producing script twice to two separate output files and byte-compare them.
`verify-deterministic.ps1` wraps this: it runs the harness twice and compares with
a byte-exact hash (the equivalent of Windows `fc /b`). If outputs legitimately
embed a timestamp or run id, pass `-NormalizeRegex` so those volatile fields are
masked before comparison rather than weakening the test.

## Graceful headless degradation (what the plugin must do)

A plugin that is also used interactively must detect the headless host and skip
GUI work, or it will crash the engine and break CI. The established guard is a
process-name check at every UI entry point:

```csharp
bool isHeadless = string.Equals(
    Process.GetCurrentProcess().ProcessName,
    "accoreconsole",
    StringComparison.OrdinalIgnoreCase);

if (isHeadless) return;   // skip PaletteSet / ribbon / palette creation
```

Ribbon initialization is the other common offender: `ComponentManager.Ribbon` is
`null` headlessly, so wrap ribbon setup in a null-check and try/catch so it
degrades instead of throwing. `references/pitfalls.md` has the full matrix.

## Bundled resources

- `scripts/run-headless.ps1` — parameterized harness: auto-detects the engine,
  runs a `.scr`, captures output, enforces a timeout, adjudicates the crash
  marker, returns a clear PASS/FAIL with the reason.
- `scripts/headless-test.scr.template` — copy this for every test. Has the
  NETLOAD line, a command slot, and the crash marker already in place.
- `scripts/verify-deterministic.ps1` — runs a producing script twice and proves
  byte-for-byte identity, with optional field normalization.
- `references/pitfalls.md` — the headless limitation matrix (suppressed commands,
  rendering, UI crashes, autoloader, licensing/edition caps) and the workaround
  for each. Read before debugging any headless-only failure.
- `references/verification-checklist.md` — the pre-flight checklist to walk before
  declaring any headless test passed. Copy-pasteable into a PR or task report.

## Scope: verification, not API authoring

This skill covers the *engine interaction and verification* layer — running a
plugin headlessly and proving the result. It is not an API-authoring skill and
does not supply or invent Civil 3D / AutoCAD C# signatures.
