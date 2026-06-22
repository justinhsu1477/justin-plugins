---
name: clarify-spec
description: Use at the START of any non-trivial feature, bug fix, or task before writing code — clarify the requirement, surface ambiguities, and pin down acceptance criteria as Given–When–Then behaviour scenarios (BDD). Triggers when the request is vague, multi-step, the "done" condition is not explicit, or BDD / behaviour-driven specs are wanted.
---

# Clarify the spec before coding

Before touching code, make sure you are solving the right problem.

1. **Restate the goal in one sentence.** If you can't, the spec is too vague — ask.
2. **Surface the 2–4 highest-impact unknowns** — inputs, edge cases, scope boundaries, and non-functional needs (latency, scale, security/privacy). Ask them; don't assume.
3. **Write acceptance criteria as Given–When–Then scenarios (this is BDD).** Each scenario = starting context (**Given**) → action (**When**) → observable result (**Then**). Cover the happy path, key edge cases, and error cases; state what is out of scope. *e.g. Given a message with a link and an urgency word, When pre-filtered, Then it is flagged suspicious.* These scenarios **are** the spec, and each maps 1:1 to a failing test in `tdd-first`.
4. **Only proceed once the goal + acceptance criteria are clear.**

Skip the ceremony for one-line trivial changes. Apply it whenever the change is non-trivial or the requirement is fuzzy — defining "what correct means" up front is the cheapest bug prevention there is.
