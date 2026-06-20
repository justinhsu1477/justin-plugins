#!/usr/bin/env bash
# One-shot installer — installs the whole plugin bundle on a fresh machine.
# Use this if the folder-trust auto-install (via .claude/settings.json) doesn't fire.
# Run AFTER:  git clone https://github.com/justinhsu1477/justin-plugins.git && cd justin-plugins
set -uo pipefail

echo "==> Official plugins (built-in 'claude-plugins-official' marketplace)…"
for p in code-review security-guidance context7 pyright-lsp typescript-lsp jdtls-lsp; do
  echo "  - $p"
  claude plugin install "$p@claude-plugins-official" 2>/dev/null \
    || echo "    WARN: '$p' failed — verify slug:  claude plugin list --available"
done

echo "==> My own plugins (justin-tools)…"
claude plugin marketplace add justinhsu1477/justin-plugins 2>/dev/null || true
for p in backend-review spring-test-patterns dev-workflow mcp-builder; do
  echo "  - $p"
  claude plugin install "$p@justin-tools" 2>/dev/null || echo "    WARN: '$p' failed"
done

echo
echo "==> LSP language servers are NOT bundled — install the ONE for today's language:"
echo "    Python:     pip install pyright"
echo "    TypeScript: npm i -g typescript-language-server typescript"
echo "    Java:       brew install jdtls        # needs a JDK on PATH"
echo
echo "==> Done. Inside Claude Code run  /reload-plugins  then check  /plugin  Errors tab."
