# claude-plugins

A personal [Claude Code](https://claude.com/claude-code) plugin **marketplace** (test).

## Add this marketplace

```bash
claude plugin marketplace add justinhsu1477/claude-plugins
```

Or inside Claude Code: `/plugin` → Add marketplace.

> Self-hosted git / GitLab works too — use the full URL form:
> `claude plugin marketplace add https://gitlab.example.com/team/claude-plugins.git`

## Install a plugin

```bash
claude plugin install backend-review@justin-tools
```

(`justin-tools` is the marketplace name from `marketplace.json`; `claude-plugins` is the repo.)

## Plugins

### `backend-review`

An **independent, fresh-context** code reviewer for Java/Spring backends. It judges a diff against a requirement on its own merits — separating generation from verification.

| Component | What it does |
|---|---|
| **skill** `code-review` | concurrency / data-consistency / data-access-security checklist |
| **agent** `java-backend-reviewer` | transaction & layering specialist; Read/Grep/Bash only, never edits |
| **command** `/review-diff "<requirement>"` | reviews the working-tree diff against a requirement |

#### Usage

```
/review-diff "Add idempotent retry to the payment-capture service"
```
