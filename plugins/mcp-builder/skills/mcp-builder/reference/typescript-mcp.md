# TypeScript — MCP SDK (`@modelcontextprotocol/sdk`)

Use when the service/tooling is Node-native. Zod defines and validates input schemas.

## Setup

```bash
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript tsx @types/node
```

`package.json`: set `"type": "module"`, and `"scripts": { "build": "tsc", "dev": "tsx src/index.ts" }`.
`tsconfig.json`: `"target": "ES2022"`, `"module": "Node16"`, `"moduleResolution": "Node16"`, `"strict": true`, `"outDir": "dist"`.

## Complete template (`src/index.ts`)

```ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({ name: "github-issues", version: "1.0.0" });

const API = "https://api.github.com";
const TOKEN = process.env.GITHUB_TOKEN ?? ""; // secrets from env, not args

// ---- shared infrastructure ----
async function ghGet(path: string, params: Record<string, string>) {
  const url = new URL(API + path);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  const headers: Record<string, string> = { Accept: "application/vnd.github+json" };
  if (TOKEN) headers.Authorization = `Bearer ${TOKEN}`;
  const res = await fetch(url, { headers });
  if (!res.ok) throw Object.assign(new Error(`GitHub ${res.status}`), { status: res.status });
  return res.json();
}
const fmtIssue = (i: any) => `#${i.number} [${i.state}] ${i.title} — ${i.html_url}`;

// ---- tools: workflow-shaped, strict input schema ----
server.registerTool(
  "find_issues",
  {
    title: "Find GitHub issues",
    description:
      "Find issues in a repo by keyword/state. Use before reading or commenting on issues.",
    inputSchema: {
      repo: z.string().describe('"owner/name", e.g. "anthropics/anthropic-sdk-python"'),
      query: z.string().default("").describe("free-text to match; empty = all"),
      state: z.enum(["open", "closed", "all"]).default("open"),
      limit: z.number().int().min(1).max(100).default(20),
    },
  },
  async ({ repo, query, state, limit }) => {
    if (!repo.includes("/")) {
      return { content: [{ type: "text", text: `Error: repo must be 'owner/name', got '${repo}'.` }] };
    }
    const q = `repo:${repo} is:issue state:${state} ${query}`.trim();
    try {
      const data: any = await ghGet("/search/issues", { q, per_page: String(limit) });
      const items: any[] = data.items ?? [];
      const text = items.length
        ? items.map(fmtIssue).join("\n")
        : `No issues in ${repo} matching '${query}' (state=${state}).`;
      return { content: [{ type: "text", text }] };
    } catch (e: any) {
      const msg =
        e.status === 404
          ? `Repo '${repo}' not found or private. Check owner/name and token scope.`
          : `GitHub API error. Query was: ${q}`;
      return { content: [{ type: "text", text: msg }], isError: true };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("github-issues MCP server running on stdio"); // logs MUST go to stderr
}
main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
```

## Run & register

```bash
npm run build                                              # smoke-test: compiles to dist/
claude mcp add github-issues -e GITHUB_TOKEN=ghp_xxx -- node /abs/path/dist/index.js
# dev without build: claude mcp add github-issues -- npx tsx /abs/path/src/index.ts
```

## Gotchas & checklist
- **Never `console.log` on a stdio server** — stdout is the protocol channel. All logging → `console.error` (stderr).
- `inputSchema` is a **raw shape** `{ field: z.string() }`, not `z.object({...})`, in SDK v1.x. (In the 2.0 line the import is `@modelcontextprotocol/server` and inputSchema takes `z.object(...)` — match whatever `npm ls @modelcontextprotocol/sdk` shows.)
- [ ] Zod constraints on every input (`.min/.max/.enum`, `.describe`)
- [ ] Handler returns `{ content: [{ type: "text", text }] }`; set `isError: true` on failures
- [ ] Secrets from `process.env`; output bounded and high-signal
