# justin-plugins

個人 [Claude Code](https://claude.com/claude-code) plugin **marketplace**（marketplace 名稱：`justin-tools`）。

兩個用途：

1. **自製後端 plugin** —— 獨立 code review 子代理 + Spring 整合測試慣例。
2. **一鍵環境** —— 一份 `.claude/settings.json` 把常用的官方 plugin（MCP / LSP / 安全審查）和自製 plugin 打包；clone 進任何電腦、接受 trust 就全裝。

---

## 📦 內容總覽

| 類型 | 名稱 | 來源 | 一句話 |
|---|---|---|---|
| 🤖 **MCP server** | `context7` | 官方 | 即時抓最新 library 文件，防 AI 幻覺出不存在的 API |
| 👤 **Subagent** | `java-backend-reviewer` | 自製 | 乾淨 context 的 Java/Spring 後端審查者（唯讀） |
| ⌨️ **Command** | `/review-diff "<需求>"` | 自製 | 對 working-tree diff 做獨立審查 |
| 🧠 **Skill** | `code-review` | 自製 | 並發 / 一致性 / 資料存取安全的審查清單（含紅線） |
| 🧠 **Skill** | `spring-boot-integration-test-patterns` | 自製 | Testcontainers + WireMock 整合測試慣例 |
| 🛡️ **安全護欄** | `security-guidance` | 官方 | 每次改動自動掃漏洞並當場要求修正 |
| 🔎 **Code review** | `code-review` | 官方 | PR / diff 自動審查 |
| 🔧 **LSP** | `pyright-lsp` · `typescript-lsp` · `jdtls-lsp` | 官方 | Python / TS / Java 型別檢查、跳定義、即時錯誤 |

> 自製的掛在 `justin-tools` marketplace；官方的透過 `.claude/settings.json` 的 `enabledPlugins` 從內建的 `claude-plugins-official` 取得。

---

## 🎯 一鍵安裝

把整包（官方 + 自製）一次裝到一台乾淨機器。

**主要方式 — clone + trust（自動裝 `.claude/settings.json` 裡所有 `enabledPlugins`）：**

```bash
git clone https://github.com/justinhsu1477/justin-plugins.git
cd justin-plugins          # 一定要 cd 進去，別用 --add-dir（不會觸發 folder-trust）
claude                     # 接受 trust 提示 → 安裝全部
```

**備案 — 明確安裝腳本（不依賴 trust 提示）：**

```bash
git clone https://github.com/justinhsu1477/justin-plugins.git && cd justin-plugins
bash setup.sh
```

> ⚠️ **LSP language server 不含在內**，裝當天語言那一個即可：
> `pip install pyright` · `npm i -g typescript-language-server typescript` · `brew install jdtls`
> 裝完 `/reload-plugins`，再看 `/plugin` 的 **Errors** 分頁。

> ⚠️ **建議先測一次**：找個丟棄資料夾跑完整流程，確認 `/plugin` 列出全部、Errors 乾淨。slug / marketplace 偶爾會變，順手 `claude plugin list --available` 對一下。

---

## 🧩 自製 plugins 詳述

### `backend-review` — 獨立後端 reviewer

把「寫」跟「審」分開：用一個**乾淨 context** 的子代理只看 diff + 需求，不受作者意圖影響（separate generation from verification）。

- **Subagent `java-backend-reviewer`**（model: `opus`；工具：Read / Grep / Bash，只讀不改）
  審查重點：`@Transactional` 邊界 / 傳播 / 隔離級別與 self-invocation 陷阱、分層（Controller / Service / Repository 不越界）、DTO ↔ Entity 分離、並發與資料一致性、OWASP Top 10、資料存取護欄。
- **Command `/review-diff "<需求>"`**
  抓 `git diff HEAD`，用上面的子代理 + `code-review` skill 對需求獨立審查。輸出固定為：Summary / Issues（Blocking · Non-blocking）/ Security concerns / Suggested patches。
- **Skill `code-review`**（工程直覺清單，審查時自動套用）
  - **並發正確性**：race、check-then-act、鎖範圍 / 死鎖、`@Transactional` + async、retry 的 idempotency
  - **資料一致性**：交易邊界對齊一個工作單元、隔離級別 / read-your-writes、跨 aggregate 不變量
  - **資料存取紅線**：generated SQL 一律 read-only（拒 INSERT / UPDATE / DELETE / DDL）、每查詢強制 tenant / role filter、PII 遮罩、查詢 audit

```bash
/review-diff "Add idempotent retry to the payment-capture service"
```

### `spring-test-patterns` — Spring Boot 整合測試慣例

- **Skill `spring-boot-integration-test-patterns`**
  Testcontainers 跑真 Mongo / Postgres、WireMock 以 JSON fixtures stub 外部服務、per-test 自動註冊 fixtures、`@TestNamespace` 分區、強制跨租戶覆蓋。核心原則：**測試鎖的是 wire contract，不是 Java DTO 形狀** —— 任何漂移 outbound 格式的改動都要以 stub mismatch 浮現。定位在 inline stub（L1–2）與 Pact / Spring Cloud Contract（L5）之間的 convention-driven **L4**。

---

## 🧰 打包的官方 plugins（透過 `.claude/settings.json`）

clone + trust 這個 repo 時會一併啟用（來自內建 `claude-plugins-official`）：

| Plugin | 類型 | 作用 |
|---|---|---|
| `context7` | MCP server | 即時 library 文件 |
| `security-guidance` | 安全護欄 | 邊寫邊掃漏洞、要求修正 |
| `code-review` | review | diff / PR 自動審查 |
| `pyright-lsp` / `typescript-lsp` / `jdtls-lsp` | LSP | 型別檢查、跳定義、即時錯誤 |

---

## 🔧 marketplace / 單獨安裝

```bash
claude plugin marketplace add justinhsu1477/justin-plugins
claude plugin install backend-review@justin-tools
claude plugin install spring-test-patterns@justin-tools
```

（`justin-tools` 是 `marketplace.json` 裡的 marketplace 名稱；`justin-plugins` 是 repo 名稱。
自架 git / GitLab 也可，用完整 URL：`claude plugin marketplace add https://gitlab.example.com/team/justin-plugins.git`）
