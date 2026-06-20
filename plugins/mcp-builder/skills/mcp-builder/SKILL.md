---
name: mcp-builder
description: Use when building or designing an MCP (Model Context Protocol) server — exposing an API, database, or service as agent-callable tools in Python (FastMCP), TypeScript, or Java/Spring AI. Covers agent-centric tool design, self-contained implementation templates, and evaluation.
---

# MCP Builder

An MCP server exposes **tools an LLM calls** to act on an external service. Quality is measured one way: **can an agent accomplish real tasks with these tools?** Not "did I wrap every endpoint." Design for the agent as the user.

Work in four phases. Don't skip 1 or 4 — they are where most servers are won or lost.

## Phase 1 — Research & plan (before any code)

- Learn the target: endpoints, **auth** (key / OAuth / token), **pagination**, rate limits, error shapes, core data models. Use WebFetch/WebSearch for unfamiliar APIs.
- Choose tools by **workflow, not endpoint**. Consolidate related calls into one capable tool (e.g. `find_issues(repo, query, state)` beats `list/get/filter/search` as four tools). Fewer, sharper tools = a more usable server.
- Write the plan first: tool names (consistent prefix), each tool's inputs (with types/constraints) and output shape, shared helpers (request, pagination, formatting), error strategy. Confirm the list before implementing.

Full rules: **`reference/design-principles.md`** (read it — this is the part that separates a good server from a thin wrapper).

## Phase 2 — Implement

Pick the language and follow its self-contained template (deps, structure, auth, one full example tool, run command):

- **Python (FastMCP)** → `reference/python-fastmcp.md` — default; fastest to stand up.
- **TypeScript (MCP SDK)** → `reference/typescript-mcp.md`.
- **Java (Spring AI)** → `reference/java-spring-ai.md` — `@Tool` methods on Spring beans; best when the service is already a Spring app.

Order inside a server: build shared infrastructure (HTTP client, error helper, response formatter, pagination) **first**, then add tools one at a time against it.

## Phase 3 — Review

Apply the design principles + the language checklist. Specifically check:
- **Output is high-signal and bounded** — return what the agent needs, offer concise vs. detailed, cap a single response at ~25k tokens. Token bloat is the #1 server killer.
- **Errors are actionable** — tell the agent the *next step* ("repo not found — pass owner/name, e.g. anthropics/sdk"), never a raw stack trace.
- **Schemas are strict** — validate inputs (Pydantic / Zod / Spring); use human-readable identifiers, not opaque IDs, where possible.
- **Tool annotations** set where supported (`readOnlyHint`, `destructiveHint`, `idempotentHint`).

> Testing gotcha: an MCP server over stdio is a **long-running process** — running it directly will hang your shell. Smoke-test syntax/build (`python -c`, `npm run build`, `mvn -q compile`), then verify by registering it (below). Don't just `python server.py` and wait.

## Phase 4 — Evaluate

Write **3–5 realistic questions a real user would ask**, each: read-only, complex enough to need a tool, and verifiably answerable. Run them through the server. If a question can't be answered cleanly, the tool design is wrong — go back to Phase 1. This loop is the point, not a formality.

## Register & use immediately

Local stdio server, into Claude Code:

```bash
# Python
claude mcp add <name> -- python /abs/path/server.py
# TypeScript (after build)
claude mcp add <name> -- node /abs/path/dist/index.js
# Java/Spring AI stdio (after package)
claude mcp add <name> -- java -jar /abs/path/target/<app>.jar
```

Or project-scoped via `.mcp.json` at repo root:

```json
{ "mcpServers": { "<name>": { "command": "python", "args": ["server.py"] } } }
```

Then `/mcp` in Claude Code to confirm it connected and the tools are listed.

## Pre-ship checklist

- [ ] Tools map to workflows; names share a prefix and read like tasks
- [ ] Every input validated; descriptions tell the agent how/when to use the tool
- [ ] Output bounded & high-signal; concise/detailed option where it helps
- [ ] Errors are actionable next-steps, not stack traces
- [ ] Auth + pagination + rate-limit handling present
- [ ] Smoke-tested without hanging; registers and connects via `/mcp`
- [ ] 3–5 evals pass
