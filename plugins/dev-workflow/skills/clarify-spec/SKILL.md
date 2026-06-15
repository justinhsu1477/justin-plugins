---
name: clarify-spec
description: Use at the START of any non-trivial feature, bug fix, or task before writing code — clarify the requirement, surface ambiguities, and pin down acceptance criteria. Triggers when the request is vague, multi-step, or the "done" condition is not explicit.
---

# Clarify the spec before coding

Before touching code, make sure you are solving the right problem.

1. **Restate the goal in one sentence.** If you can't, the spec is too vague — ask.
2. **Surface the 2–4 highest-impact unknowns** — inputs, edge cases, scope boundaries, and non-functional needs (latency, scale, security/privacy). Ask them; don't assume.
3. **Write explicit acceptance criteria** — the observable conditions that mean "done": example inputs → outputs, error cases, and what is explicitly out of scope.
4. **Only proceed once the goal + acceptance criteria are clear.**

Skip the ceremony for one-line trivial changes. Apply it whenever the change is non-trivial or the requirement is fuzzy — defining "what correct means" up front is the cheapest bug prevention there is.
