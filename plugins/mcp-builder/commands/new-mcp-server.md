---
description: Scaffold a high-quality MCP server for a given API/service, following the mcp-builder skill.
argument-hint: "<API or service> [python|typescript|java]"
allowed-tools: Read, Write, Edit, Grep, Bash, WebFetch, WebSearch
---

## Target
$ARGUMENTS

## Task
Build an MCP server for the target above using the **mcp-builder** skill. If no language is given, default to **python** (FastMCP).

Work the skill's four phases in order:

1. **Research & plan** — study the target API (endpoints, auth, pagination, errors). Pick the few tools that enable real *workflows*, not one-tool-per-endpoint. State the tool list + each tool's inputs/outputs before coding.
2. **Implement** — load the matching reference for the chosen language and follow its template: shared HTTP/error/format helpers first, then each tool with a strict input schema, a docstring/description an agent can act on, and concise high-signal output (cap ~25k tokens).
3. **Review** — apply `reference/design-principles.md` and the language checklist. Fix actionable error messages, pagination, and token bloat.
4. **Evaluate** — write 3–5 read-only, verifiable eval questions a user would actually ask, and confirm the tools answer them.

Finish by printing the exact `claude mcp add …` command to register the server locally so it can be used immediately.
