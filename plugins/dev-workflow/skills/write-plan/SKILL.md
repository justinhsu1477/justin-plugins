---
name: write-plan
description: Use after the spec is clear and before implementing a non-trivial or multi-file change — explore the code first, then produce a short step-by-step plan and confirm the approach. Triggers when a change spans multiple files, the approach is uncertain, or you are in unfamiliar code.
---

# Plan before you implement

Separate research and planning from execution — jumping straight to code often solves the wrong problem.

1. **Explore first.** Read the relevant files and existing patterns; note how similar things are already done in this codebase (reuse beats reinvent).
2. **Write a concise plan**: the files to change, the order, the key interfaces/signatures, and the **end-to-end verification step** that will prove it works.
3. **Call out risks and trade-offs explicitly** — what you're choosing and what you're giving up.
4. **Confirm the plan** (or adjust) before writing code.

Skip for one-sentence changes. Use it when the work is uncertain, multi-file, or in code you don't yet understand. A plan you can describe in one sentence doesn't need this.
