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
| 🧭 **Workflow Skill ×4** | `dev-workflow`：clarify-spec · write-plan · tdd-first · verify-evidence | 自製 | 開發紀律：釐清需求 → 計畫 → 測試先行 → 證據驗證 |
| 🛠️ **Skill + Command** | `mcp-builder` · `/new-mcp-server` | 自製 | 做高品質 MCP server：agent 導向工具設計 + Python / TS / Java(Spring AI) 範本 |
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

LSP plugin 只配連線，language server binary 要另外裝（見下方「打包的官方 plugins」）。

---

## ✅ 驗證安裝（在新機器上確認一鍵成功）

裝完後逐項確認：

```bash
# 1) 10 個 plugin 全 enabled（4 自製 + 6 官方）
claude plugin list

# 2) context7 MCP 已連線
claude mcp list | grep context7
```

在 Claude Code 內：

- 打 `/` 應看到：`/review-diff`、`/new-mcp-server`、`clarify-spec`、`write-plan`、`tdd-first`、`verify-evidence`、`code-review`、`spring-boot-integration-test-patterns`。
- `/plugin` →「Installed」：10 個都在、enabled；「Errors」：空的（LSP 若顯示 `Executable not found in $PATH` 只是還沒裝 language-server binary，裝了就消失）。
- 在任一 git repo 改一行、跑 `/review-diff "smoke test"`，能正常產出 review = 自製 plugin 生效。

**完成標準**：10 個 plugin 全 enabled、`/` 看得到上述 skill、Errors 分頁除了「待裝 LSP binary」外乾淨。

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

### `dev-workflow` — AI 輔助開發紀律（4 個 skill）

把「好的開發流程」變成會自動觸發的 skill。核心理念：**把 AI 產出當不可信輸入，保留人工把關。**

- **`clarify-spec`** —— 動手前先釐清需求、定 acceptance criteria（先定義「什麼叫對」）。
- **`write-plan`** —— 多檔 / 不確定的改動前，先 explore 再出計畫、確認方向。
- **`tdd-first`** —— 有會壞的邏輯就先寫一個 failing test 釘住；純 glue / CRUD 則跳過、改直接驗證。
- **`verify-evidence`** —— 宣稱完成前跑真實驗證並貼出證據；「解釋不出、驗不了就不 ship」。

### `mcp-builder` — 做高品質 MCP server

把「怎麼設計給 agent 用的工具」變成可觸發的 skill。核心理念：**MCP server 的好壞只有一個標準 —— agent 能不能靠這些 tool 完成真實任務**，不是「有沒有把每個 endpoint 都包成 tool」。

- **Skill `mcp-builder`**（說「幫我做一個 ⋯⋯ 的 MCP server」就會觸發）四階段：研究與規劃 → 實作 → 審查 → 評測。主檔講工作流與設計原則，細節分流到 `reference/`：
  - `design-principles.md` —— agent 導向設計：以 workflow 而非 endpoint 切工具、為有限 context 最佳化（高訊號、可選詳略、可讀 ID、~25k token 上限）、可行動的錯誤訊息、評測驅動、tool annotations、安全底線。
  - `python-fastmcp.md` / `typescript-mcp.md` / `java-spring-ai.md` —— 各語言**自成一體**的完整範本（相依、結構、認證、一個完整範例 tool、執行與註冊指令、checklist）。三份用同一個 GitHub issues 範例，方便對照。
- **Command `/new-mcp-server "<API/服務>" [python|typescript|java]`** —— 直接照四階段把指定服務 scaffold 成 MCP server，最後印出 `claude mcp add …` 讓你當場註冊使用。未指定語言預設 Python。
- 自我驗證：MCP server 走 stdio 是長駐程序，直接跑會卡住 shell —— 範本都用 smoke-test（編譯/build）+ 註冊後 `/mcp` 確認，不會空等。

```bash
/new-mcp-server "GitHub issues API" java
```

> Java 走 Spring AI（`spring-ai-starter-mcp-server` + `@Tool` 方法 + `MethodToolCallbackProvider`），含 stdio 的關鍵雷點：stdout 是協議通道，banner / log 一律關掉或導到檔案。

---

## 🧰 打包的官方 plugins（透過 `.claude/settings.json`）

clone + trust 這個 repo 時會一併啟用（來自內建 `claude-plugins-official`）：

| Plugin | 類型 | 作用 |
|---|---|---|
| `context7` | MCP server | 即時 library 文件 |
| `security-guidance` | 安全護欄 | 邊寫邊掃漏洞、要求修正 |
| `code-review` | review | diff / PR 自動審查 |
| `pyright-lsp` / `typescript-lsp` / `jdtls-lsp` | LSP | 型別檢查、跳定義、即時錯誤 |

LSP plugin 只設定連線，language server binary 要自己裝對應語言那個：
`pip install pyright` · `npm i -g typescript-language-server typescript` · `brew install jdtls`，裝完 `/reload-plugins`。

---

## 🔧 marketplace / 單獨安裝

```bash
claude plugin marketplace add justinhsu1477/justin-plugins
claude plugin install backend-review@justin-tools
claude plugin install spring-test-patterns@justin-tools
claude plugin install mcp-builder@justin-tools
```

（`justin-tools` 是 `marketplace.json` 裡的 marketplace 名稱；`justin-plugins` 是 repo 名稱。
自架 git / GitLab 也可，用完整 URL：`claude plugin marketplace add https://gitlab.example.com/team/justin-plugins.git`）
