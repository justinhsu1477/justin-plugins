---
name: verify-evidence
description: Use before claiming any task is complete, fixed, or passing — run the actual verification (tests, build, the app, a query) and show the output. Triggers on "done", "fixed", "should work", or right before committing / finishing.
---

# Show evidence, don't assert success

"Looks done" is not done — without a check you run, every mistake waits for the user to notice it.

1. **Run the real check** — the test suite, build, linter, the app/endpoint, or a query that actually proves the behavior.
2. **Show the evidence** — the command you ran and its real output (or a screenshot). Don't paraphrase "it passes"; paste what returned.
3. **If you can't verify it, say so explicitly.** Don't ship what you can't verify.
4. **For changes touching security/data**, also state the boundary you upheld: input validated, least-privilege / read-only, no secrets or PII in logs.

Rule of thumb: *if you can't explain it and can't verify it, it doesn't ship.*
