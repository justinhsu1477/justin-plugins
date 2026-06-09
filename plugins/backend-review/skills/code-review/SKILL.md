---
name: code-review
description: Engineering-intuition review checklist for backend changes — concurrency correctness, data consistency, and data-access security. Use when reviewing a git diff against a requirement.
---

# Code Review — engineering intuition

Review the **diff** against the stated **requirement**. Judge the artifact on its own merits — not the author's narrative for why it was written that way.

## Concurrency correctness
- Shared mutable state, race conditions, check-then-act gaps
- Lock scope / ordering, deadlock risk; `@Transactional` + async / thread-pool interplay
- Idempotency of retried operations; at-least-once side effects

## Data consistency
- Transaction boundaries match one unit of work; partial-commit windows
- Isolation-level / read-your-writes assumptions
- Cross-aggregate invariants; eventual-consistency gaps

## Data-access security (hard red lines)
- **Generated SQL is read-only** — any LLM- or dynamically-generated query MUST be SELECT-only. Reject INSERT / UPDATE / DELETE / DDL (CREATE / ALTER / DROP / TRUNCATE).
- **Mandatory authorization filter** — every query constrained by tenant / role scope. No unscoped table access.
- **PII masking** — national-id, phone, email and other sensitive fields masked in results, never returned raw.
- **Audit** — every query records who / when / what (statement + params). No silent queries.

## Output
Summary · Issues (Blocking / Non-blocking) · Security concerns · Suggested patches.
