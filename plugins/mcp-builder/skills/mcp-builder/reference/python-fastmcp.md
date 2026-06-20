# Python — FastMCP (official `mcp` SDK)

Fastest way to stand up an MCP server. The decorator turns type hints + docstring into the tool schema automatically.

## Setup

```bash
# uv (recommended) or pip
uv add "mcp[cli]" httpx
# pip install "mcp[cli]" httpx
```

Single-file `server.py` is fine for a handful of tools; split into modules when it grows.

## Complete template

```python
"""GitHub issues MCP server — find and create issues for a repo."""
import os
import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("github-issues")

API = "https://api.github.com"
TOKEN = os.environ.get("GITHUB_TOKEN", "")  # read secrets from env, never args


# ---- shared infrastructure (build this first) ----
async def _get(path: str, params: dict | None = None) -> dict | list:
    headers = {"Accept": "application/vnd.github+json"}
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.get(f"{API}{path}", headers=headers, params=params)
        r.raise_for_status()
        return r.json()


def _fmt_issue(i: dict) -> str:
    return f"#{i['number']} [{i['state']}] {i['title']} — {i['html_url']}"


# ---- tools: one capable tool per workflow ----
@mcp.tool()
async def find_issues(repo: str, query: str = "", state: str = "open", limit: int = 20) -> str:
    """Find issues in a GitHub repository.

    Use this to locate issues by keyword/state before reading or commenting.

    Args:
        repo: "owner/name", e.g. "anthropics/anthropic-sdk-python".
        query: free-text to match in title/body; empty = all.
        state: "open", "closed", or "all". Default "open".
        limit: max results, 1-100. Default 20.
    """
    if "/" not in repo:
        return f"Error: repo must be 'owner/name', got '{repo}'. Example: 'anthropics/anthropic-sdk-python'."
    limit = max(1, min(limit, 100))
    q = f"repo:{repo} is:issue state:{state} {query}".strip()
    try:
        data = await _get("/search/issues", {"q": q, "per_page": limit})
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 404:
            return f"Repo '{repo}' not found or private. Check the owner/name and token scope."
        return f"GitHub API error {e.response.status_code}. Query was: {q}"
    items = data.get("items", [])
    if not items:
        return f"No issues in {repo} matching '{query}' (state={state})."
    return "\n".join(_fmt_issue(i) for i in items)  # high-signal, bounded output


@mcp.tool()
async def create_issue(repo: str, title: str, body: str = "") -> str:
    """Create an issue. Requires GITHUB_TOKEN with write scope.

    Args:
        repo: "owner/name".
        title: issue title (required, non-empty).
        body: Markdown body. Optional.
    """
    if not TOKEN:
        return "Error: GITHUB_TOKEN not set — cannot create issues. Set it and re-register the server."
    if not title.strip():
        return "Error: title is required."
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(
            f"{API}/repos/{repo}/issues",
            headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json"},
            json={"title": title, "body": body},
        )
        if r.status_code == 403:
            return "Forbidden: token lacks write scope on this repo."
        r.raise_for_status()
        return f"Created {_fmt_issue(r.json())}"


if __name__ == "__main__":
    mcp.run()  # stdio transport by default
```

## Run & register

```bash
python -c "import server"                          # smoke-test: imports without error
GITHUB_TOKEN=ghp_xxx claude mcp add github-issues -- python /abs/path/server.py
```

Pass env into the registered server:
```bash
claude mcp add github-issues -e GITHUB_TOKEN=ghp_xxx -- python /abs/path/server.py
```

For HTTP transport instead of stdio: `mcp.run(transport="streamable-http")` and register with `claude mcp add --transport http <name> <url>`.

## Checklist
- [ ] Async tools + one shared `AsyncClient` per call; 30s timeout
- [ ] Type hints on every parameter (they *are* the schema); rich docstring with `Args:`
- [ ] Inputs validated/clamped (`limit`), readable IDs (`owner/name`)
- [ ] Secrets from `os.environ`, never tool args
- [ ] Errors return actionable strings, not raised tracebacks, for expected failures
- [ ] Output bounded and formatted (Markdown lines, not raw JSON dumps)
