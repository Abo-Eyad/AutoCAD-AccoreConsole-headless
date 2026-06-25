# Headless Verification Checklist

Walk this before declaring any headless test passed. The rule is simple: **a box
is ticked only when you can point to captured evidence for it.** "It should have
worked" is not evidence. If a box cannot be ticked, the run is not a pass — report
the gap honestly instead of asserting success.

Copy this block into the PR / task report and fill it in.

```
HEADLESS VERIFICATION — <task id> — <date>

Engine
[ ] accoreconsole.exe path recorded, version noted ......... evidence: <log header>
[ ] assembly loaded via explicit NETLOAD (not autoloader) .. evidence: <log line>

Execution
[ ] script ran through run-headless.ps1 (not hand-rolled) .. evidence: <command>
[ ] crash marker present in captured stdout ............... evidence: <marker line>
[ ] NO "Unknown command" in stdout ........................ evidence: <grep result>
[ ] exit code recorded (and NOT used as sole proof) ....... evidence: <code>
[ ] run did not time out / stall .......................... evidence: <duration>

Behavioral assertion (the thing under test)
[ ] expected side effect proven, not assumed .............. evidence: <file/value/log>
[ ] for negative tests (caps, licensing), the refusal
    evidence is in the log, not just a non-zero exit ...... evidence: <refusal line>

Determinism (only if the output claims to be reproducible)
[ ] verify-deterministic.ps1 run; two outputs byte-identical evidence: <both hashes>
[ ] any normalization regex is justified, not a cover-up ... evidence: <field masked>

Honesty gate
[ ] every box above is backed by something in a saved log file
[ ] anything NOT verified is listed explicitly as unverified, not omitted
```

## Why each gate exists

- **Crash marker, not exit code.** Native `0xC0000005` crashes can leave a clean-
  looking exit code. The marker is the only reliable proof the script reached its
  end. A missing marker is a hard fail.
- **No "Unknown command".** This silently means a suppressed command *or* an
  un-loaded assembly. The engine keeps going, so without this check the test can
  look green while testing nothing.
- **Prove the side effect.** "The command returned" says nothing about whether it
  did the right thing. Echo the written file path, read back a value, or compare
  against a golden output.
- **Negative tests need refusal evidence.** A cap or licensing test that "passed"
  because it never reached the gate is a false pass. Cross the threshold and
  capture the specific refusal.
- **Determinism is demonstrated, never promised.** If you claim reproducible
  output, two runs must hash identically; if you normalized anything, say exactly
  what and why.
- **The honesty gate is the point of this skill.** An incomplete-but-honest report
  is useful. A complete-but-fabricated one is corrosive — it makes every future
  pass untrustworthy. When in doubt, under-claim.
