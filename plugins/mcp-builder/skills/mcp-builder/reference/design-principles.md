# Agent-Centric Design Principles

The tool surface is a UX problem where the user is an LLM with a limited context window and no memory between calls. Optimize for *that* user.

## 1. Build for workflows, not endpoints
A 1:1 mapping of API endpoints to tools produces a server that technically works and is miserable to use. Consolidate.

- Group the calls a human makes to finish one task into **one tool**. `find_issues(repo, query, state="open", limit=20)` instead of `list_issues` + `search_issues` + `get_issue` + `filter_issues`.
- Each tool should do something a user would *name* ("find the open bugs assigned to me"), not something only an API author thinks about ("GET /repos/{}/issues with these 9 query params").
- Fewer, more capable tools beat many thin ones: less choice paralysis, fewer round-trips, less context burned on tool definitions.

## 2. Optimize for limited context
Context is the scarcest resource. Every token the tool returns is a token the agent can't use to think.

- Return **high-signal fields only**. Drop nulls, internal flags, and metadata nobody asked for.
- Offer a **`detail` / `format` parameter** ("concise" vs "full") so the agent can pull more only when it needs to.
- Prefer **human-readable identifiers** over opaque IDs (`"anthropics/anthropic-sdk-python"` not `repo_id=84920113`) — the agent can reason about names, and it keeps follow-up calls correct.
- **Cap response size** (~25k tokens). For large result sets, paginate or summarize; never dump an unbounded list.
- Default to **Markdown/plain text** for human-facing reads; use JSON when the agent will parse it further.

## 3. Make error messages actionable
An error is a chance to teach the agent the correct next call.

- Bad: `400 Bad Request` / a raw traceback.
- Good: `"No repo found for 'sdk'. Pass the full owner/name, e.g. 'anthropics/anthropic-sdk-python'."`
- Include: what went wrong, the likely cause, and the concrete fix. Validate inputs early and return these instead of letting the upstream API 500.

## 4. Follow natural task subdivisions
- Name tools the way a person describes the task; group related tools with a **consistent prefix** (`gh_find_issues`, `gh_create_issue`) so the set is legible.
- Tool description = a short usage guide: what it's for, when to reach for it (vs. a sibling tool), what it returns, and a note on cost/limits if relevant. The agent picks tools from descriptions alone — write them for that.

## 5. Evaluation-driven development
You cannot eyeball tool quality. Measure it.

- Write realistic, read-only, verifiable questions a user would ask; run them through the server; watch where the agent stalls, picks the wrong tool, or drowns in output.
- Every failure points at a design fix: split or merge a tool, trim output, sharpen a description, add a missing parameter. Iterate until the evals pass cleanly.

## Tool annotations (set where the SDK supports them)
Hints that help clients decide how to treat a tool:

- `readOnlyHint` — does not modify state (safe to call freely / in parallel).
- `destructiveHint` — may delete or overwrite; clients can gate it.
- `idempotentHint` — repeat calls with same args have no extra effect.
- `openWorldHint` — touches an external/open system (network) vs. a closed dataset.

## Security baseline
- Never log or echo secrets; read credentials from env, not arguments.
- Treat any generated query as untrusted — if a tool runs SQL, keep it **read-only** (reject INSERT/UPDATE/DELETE/DDL) and scope every query.
- Validate and bound all inputs (lengths, enums, ranges) before they reach the upstream service.
