# Java — Spring AI MCP Server

Best fit when the service is already a Spring app: expose existing beans as tools with one annotation. Spring AI auto-registers them with an MCP server.

Two starters — pick by transport:
- **`spring-ai-starter-mcp-server`** — STDIO (process spawned by the client). Use this for "register into Claude Code".
- **`spring-ai-starter-mcp-server-webmvc`** — HTTP/SSE (server runs as a web app).

## Dependencies (`pom.xml`)

```xml
<!-- Spring AI BOM in <dependencyManagement> -->
<dependency>
  <groupId>org.springframework.ai</groupId>
  <artifactId>spring-ai-bom</artifactId>
  <version>1.0.3</version>
  <type>pom</type>
  <scope>import</scope>
</dependency>

<!-- STDIO server starter -->
<dependency>
  <groupId>org.springframework.ai</groupId>
  <artifactId>spring-ai-starter-mcp-server</artifactId>
</dependency>
```

(Spring AI 1.0 is on Maven Central — no extra repo needed. Needs Spring Boot 3.3+ / Java 17+.)

## Tools — annotate methods on a bean

```java
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.HttpClientErrorException;

@Service
public class GitHubTools {

    private final RestClient http = RestClient.builder()
            .baseUrl("https://api.github.com")
            .defaultHeader("Accept", "application/vnd.github+json")
            .build();

    @Tool(description = "Find issues in a GitHub repository by keyword and state. "
            + "Use before reading or commenting on issues.")
    public String findIssues(
            @ToolParam(description = "\"owner/name\", e.g. anthropics/anthropic-sdk-python") String repo,
            @ToolParam(description = "free-text to match; empty = all", required = false) String query,
            @ToolParam(description = "open, closed, or all (default open)", required = false) String state) {

        if (repo == null || !repo.contains("/"))
            return "Error: repo must be 'owner/name', e.g. 'anthropics/anthropic-sdk-python'.";
        String st = (state == null || state.isBlank()) ? "open" : state;
        String q = ("repo:" + repo + " is:issue state:" + st + " " + (query == null ? "" : query)).trim();

        try {
            JsonNode data = http.get()
                    .uri(b -> b.path("/search/issues").queryParam("q", q).queryParam("per_page", 20).build())
                    .retrieve().body(JsonNode.class);

            JsonNode items = data.path("items");
            if (!items.elements().hasNext())
                return "No issues in " + repo + " matching '" + query + "' (state=" + st + ").";

            StringBuilder sb = new StringBuilder();
            items.forEach(i -> sb.append("#").append(i.path("number").asInt())
                    .append(" [").append(i.path("state").asText()).append("] ")
                    .append(i.path("title").asText())
                    .append(" — ").append(i.path("html_url").asText()).append("\n"));
            return sb.toString();                       // high-signal, bounded
        } catch (HttpClientErrorException.NotFound e) {
            return "Repo '" + repo + "' not found or private. Check owner/name and token scope.";
        } catch (HttpClientErrorException e) {
            return "GitHub API error " + e.getStatusCode() + ". Query was: " + q;
        }
    }
}
```

## Register the bean as tools

```java
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;

@SpringBootApplication
public class McpServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(McpServerApplication.class, args);
    }

    @Bean
    ToolCallbackProvider githubTools(GitHubTools tools) {
        return MethodToolCallbackProvider.builder().toolObjects(tools).build();
    }
}
```

## Config — STDIO (`src/main/resources/application.yml`)

```yaml
spring:
  ai:
    mcp:
      server:
        name: github-issues
        version: 1.0.0
        type: SYNC
        stdio: true
  main:
    web-application-type: none   # stdio server is not a web app
    banner-mode: off             # stdout is the protocol channel — keep it clean
logging:
  file:
    name: ./mcp-server.log       # route logs to a FILE, never stdout
  pattern:
    console: ""
```

> Critical stdio gotcha: the JSON-RPC protocol owns **stdout**. Any banner/log/`System.out.println` to stdout corrupts the stream and the client won't connect. Disable the banner and send logs to a file.

For HTTP instead: use `spring-ai-starter-mcp-server-webmvc`, drop the `web-application-type: none` line, and the tools are served at the SSE endpoint on your server port.

## Build & register

```bash
mvn -q -DskipTests package                                  # smoke-test: compiles & packages
claude mcp add github-issues -- java -jar /abs/path/target/mcp-server-0.0.1-SNAPSHOT.jar
```

Pass secrets as env: `claude mcp add github-issues -e GITHUB_TOKEN=ghp_xxx -- java -jar /abs/path/app.jar`, then read with `@Value("${GITHUB_TOKEN:}")` or `System.getenv`.

## Checklist
- [ ] `@Tool` description says what/when; `@ToolParam` describes each arg, `required=false` for optionals
- [ ] Bean exposed via `MethodToolCallbackProvider`
- [ ] STDIO: `web-application-type: none`, banner off, **logs to file not stdout**
- [ ] Expected failures return actionable strings; inputs validated
- [ ] Output bounded & formatted, not raw JSON dumped back
