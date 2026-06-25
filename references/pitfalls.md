# Headless Limitation Matrix

What `accoreconsole.exe` does differently from the full GUI product, why, and how
to handle it. Consult this before debugging any failure that appears *only*
headlessly. Each row is a behavior verified in practice, not a guess.

## Table of contents
1. Suppressed commands
2. Graphics / rendering pipeline
3. UI instantiation crashes (fatal)
4. Ribbon and palette components
5. The autoloader does not run
6. Licensing and edition caps
7. Quick reference table

---

## 1. Suppressed commands

Some commands that exist in the GUI are simply not registered in the headless
engine. The signature symptom is the engine printing:

```
Unknown command "SOMECOMMAND".
```

Content-publishing commands are the known case: `PUBLISHPARTCONTENT` is not
available headlessly. If a feature depends on such a command, you cannot test or
ship it through the headless path — you need a programmatic alternative (e.g.
generate the artifact directly via the API / a direct data path rather than the
publishing command).

`run-headless.ps1` scans stdout for `Unknown command` and fails the run, because
the engine otherwise continues and the test can look like it "passed".

## 2. Graphics / rendering pipeline

There is no display pipeline headlessly. Anything that drives the graphics system
(`GraphicsSystem` / GS) or visual-style rendering for offscreen image capture
will fail. You cannot screenshot the viewport.

Workaround when you need an image headlessly: render it yourself. A custom GDI+
flat-shaded painter that triangulates BRep faces (e.g. via a `Mesh2d`
tessellation) produces a deterministic preview without the GS. Verify such output
by asserting the produced image's dimensions and file size, and prove determinism
with `verify-deterministic.ps1`.

## 3. UI instantiation crashes (FATAL)

Instantiating GUI host objects headlessly can raise an **uncatchable native
access violation** (`0xC0000005`). The canonical case is `PaletteSet`:
constructing one with no GUI host kills the process. Managed `try/catch` does
**not** help — the process is gone, so you only learn about it from the **absence
of the crash marker** in stdout.

Mitigation — guard every UI entry point with a process-name check and bail before
touching GUI types:

```csharp
bool isHeadless = string.Equals(
    Process.GetCurrentProcess().ProcessName,
    "accoreconsole",
    StringComparison.OrdinalIgnoreCase);

if (isHeadless) return;   // never construct PaletteSet/palettes headlessly
```

## 4. Ribbon and palette components

`ComponentManager.Ribbon` is `null` headlessly. Ribbon/tab initialization that
assumes a non-null ribbon throws. Wrap ribbon setup in a null-check plus
try/catch so the plugin degrades gracefully instead of throwing during load:

```csharp
var ribbon = ComponentManager.Ribbon;
if (ribbon == null) return;   // headless or ribbon not yet ready
try { /* build tabs/panels */ } catch { /* degrade, do not crash load */ }
```

The goal is that loading the plugin headlessly is a no-op for all GUI surface, so
`NETLOAD` and the startup command run cleanly without `eDuplicateKey` or null
reference exceptions.

## 5. The autoloader does not run

The GUI `ApplicationPlugins` (bundle) autoloader is a GUI feature and does **not**
fire in `accoreconsole`. Headless tests must `NETLOAD` the assembly explicitly in
the `.scr`. Forgetting this produces "Unknown command" for your own commands —
which looks like a code bug but is really an un-loaded assembly. The bundled
`.scr` template has the `NETLOAD` line in place.

Note on security: `NETLOAD` is governed by `SECURELOAD`. By default it refuses to
load from untrusted locations. Prefer adding the plugin folder to `TRUSTEDPATHS`;
only drop `SECURELOAD` to 0 inside a disposable test sandbox, never in anything
shipped.

## 6. Licensing and edition caps

Business-logic gates run headlessly just as they do in the GUI, and they will
interrupt a headless run — which is correct, but means tests must account for
them. Verified cases from practice:

- **Edition/size caps**: a free-edition catalog-size cap correctly halts the
  headless execution path once the limit is hit; the paid edition runs unbounded.
  A test that "passes" only because it never reached the cap is not testing the
  cap — drive enough volume to cross it.
- **Licensing**: with a missing or invalid `license.json`, the plugin should block
  catalog writes headlessly. Test both the licensed and unlicensed paths.

Because these are *intended* failures, assert on the specific refusal evidence in
the log, not merely on a non-zero exit.

## 7. Quick reference table

| Behavior headlessly            | Symptom                                  | Handling |
|--------------------------------|------------------------------------------|----------|
| Some commands suppressed       | `Unknown command "X"`                    | Use a programmatic/API path; harness fails the run |
| No graphics system             | GS / visual-style render fails           | Custom GDI+ BRep-triangulation renderer |
| `PaletteSet` construction      | Silent death, **no crash marker**, 0xC0000005 | Process-name guard, skip UI when headless |
| `ComponentManager.Ribbon`      | `null`; ribbon init throws               | Null-check + try/catch, degrade gracefully |
| Autoloader                     | Your commands are "Unknown command"      | Explicit `NETLOAD` in the `.scr` |
| Edition cap / licensing        | Run halts mid-way (by design)            | Assert on the refusal evidence; test both sides |
