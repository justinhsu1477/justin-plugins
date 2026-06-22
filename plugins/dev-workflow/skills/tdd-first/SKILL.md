---
name: tdd-first
description: Use when implementing logic that could break in non-obvious ways — business rules, calculations, validators, parsers, state transitions, algorithms, tricky conditionals — or when fixing a bug. Write a failing test first, then make it pass.
---

# Test-first for risky logic

**Decision rule — ask: "Is there non-obvious logic here that could break?"**

- **YES** → take one **Given–When–Then** scenario from `clarify-spec` and write ONE focused **failing** test from it (**Given** = arrange, **When** = act, **Then** = assert; include an edge case), then implement until it goes green. With AI, let it draft the test, but **you review the cases for meaningfulness** — a test that doesn't assert the right thing is worse than none.
- **NO** (boilerplate / glue / CRUD / config / simple mappers) → skip the unit test; instead run it and verify the behavior directly.

Two principles:
- **Treat AI-generated code as an untrusted input.** The test is also your net for catching the AI's mistakes before they ship.
- **For bugs:** first write a failing test that *reproduces* the bug, then fix it — so it can't silently come back.
