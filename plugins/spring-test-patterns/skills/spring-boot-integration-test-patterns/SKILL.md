---
name: spring-boot-integration-test-patterns
description: Use when introducing integration tests to a Spring Boot Java project — controller/service/repository layers exercised end-to-end with real databases (Testcontainers) and external services stubbed via WireMock with JSON fixtures. Triggers include "set up integration test", "BaseIntegrationTest", "WireMock", "Testcontainers", "@TestNamespace", "test the controller end-to-end", or any new `*IntegrationTest.java` file. Captures a convention-driven L4 design (per-test fixture directories, auto-registration, `api-mock/` partitioning) that combines WireMock with Snapshot/VCR-style auto-discovery — sitting above typical inline-stub use but below full contract testing (Pact / Spring Cloud Contract).
---

# Spring Boot Integration Test Patterns

## Overview

Integration tests for Spring Boot Java services that boot the full Spring context, run real Mongo / Postgres via Testcontainers, and stub external HTTP services with WireMock. Exercises controller → service → repository → DB layers as a single behavioral unit; mocks only what crosses a service boundary (other microservice / 3rd-party SDK).

**Core principle:** Tests lock the wire contract, not the Java DTO shape. Any code change that drifts the outbound wire format must surface as a stub mismatch, not silently pass through a DTO round-trip.

**Industry positioning:** This is a **convention-driven L4 design** — between typical "inline `stubFor(...)` in test bodies" (L1-L2, ~70% of WireMock users) and full contract testing with brokers (L5, Pact / Spring Cloud Contract). The pattern borrows from Snapshot Testing / Approval Testing / VCR cassettes (auto-derive fixture path from test identity) applied to WireMock. Appropriate for small-to-mid SaaS teams with 5+ controllers and a stable upstream service contract.

## When to Use

- Adding the first integration test to a Spring Boot module (greenfield setup)
- Adding a controller test to an existing suite (extends established `BaseIntegrationTest`)
- Reviewing or refactoring existing integration tests
- Stubbing an external HTTP dependency (microservice / 3rd-party API)
- Deciding whether unit vs. integration is the right level for a given concern

**Skip for:**
- Pure utility classes with no side effects (a unit test is fine)
- Code that integrates with an unavoidable 3rd-party SDK that cannot be exercised via a container (e.g. Google Cloud SDK auth flow) — unit-mock that specific seam only
- Cross-service contract testing where the provider team participates — that's Pact / Spring Cloud Contract territory, not this pattern

## The Seven-Layer Pattern

A well-structured Spring Boot integration test suite has these seven pieces:

### 1. `BaseIntegrationTest` (abstract parent with auto-register lifecycle)

Spins up shared containers, owns the WireMock wrapper, configures Spring context, exposes `MockMvc` + tenant injection, and **auto-registers per-test fixtures via JUnit `TestInfo`**.

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
public abstract class BaseIntegrationTest {

  protected static final MongoDBContainer MONGODB_CONTAINER = new MongoDBContainer("mongo:7.0");
  protected static final PostgreSQLContainer<?> POSTGRES_CONTAINER = new PostgreSQLContainer<>("postgres:15");

  /** One wrapper owns the WireMockServer lifecycle + stub loading. */
  protected static final WireMockStubs WIRE_MOCK = new WireMockStubs();

  static {
    MONGODB_CONTAINER.start();
    POSTGRES_CONTAINER.start();
  }

  private String testMethodName;

  @DynamicPropertySource
  static void registerDynamicProperties(DynamicPropertyRegistry registry) {
    registry.add("spring.data.mongodb.uri", MONGODB_CONTAINER::getReplicaSetUrl);
    registry.add("spring.datasource.url", POSTGRES_CONTAINER::getJdbcUrl);
    registry.add("spring.datasource.username", POSTGRES_CONTAINER::getUsername);
    registry.add("spring.datasource.password", POSTGRES_CONTAINER::getPassword);
    registry.add("test.mock-server.base-url", WIRE_MOCK::baseUrl);
  }

  @BeforeAll static void startWireMockServer() { WIRE_MOCK.start(); }
  @AfterAll  static void stopWireMockServer()  { WIRE_MOCK.stop(); }

  @BeforeEach
  void setUpTestState(TestInfo testInfo) {
    WIRE_MOCK.resetAll();
    cleanMongoDatabase();
    cleanPostgresDatabase();
    MDC.put("username", "test-user");
    MDC.put("groupId", "g-test");
    this.testMethodName = testInfo.getTestMethod().orElseThrow().getName();
    autoRegisterStubs();   // ← auto-load fixtures for THIS test
  }

  @AfterEach
  void resetTestState() {
    WIRE_MOCK.resetAll();
    cleanMongoDatabase();
    cleanPostgresDatabase();
    MDC.clear();
  }

  /**
   * Loads every stub fixture under {@code stubs/{namespace}/{feature}/{caseExpected}/api-mock/}
   * for the running test method. Test bodies don't invoke this — it's lifecycle.
   * A method whose name doesn't split on an underscore opts out; a missing directory
   * is a silent no-op (DB-only tests).
   */
  private void autoRegisterStubs() {
    int splitIndex = testMethodName.indexOf('_');
    if (splitIndex < 0) return;
    String namespace = resolveNamespace();
    String feature = testMethodName.substring(0, splitIndex);
    String caseExpected = testMethodName.substring(splitIndex + 1);
    WIRE_MOCK.registerAll(namespace + "/" + feature + "/" + caseExpected);
  }

  private String resolveNamespace() {
    TestNamespace annotation = this.getClass().getAnnotation(TestNamespace.class);
    if (annotation == null) {
      throw new IllegalStateException(
          "@TestNamespace missing on " + this.getClass().getSimpleName());
    }
    return annotation.value();
  }
}
```

Key decisions:
- Containers as `static` fields, started once in `static {}` block — reused across all test classes
- `@DynamicPropertySource` wires container URIs into Spring config at boot
- `WireMockStubs` (the wrapper) starts once per class — `resetAll()` between tests
- MDC seeded in `@BeforeEach` so framework auditing / tenant-scope hooks fire correctly
- Per-test cleanup truncates both stores; no test leaks state to the next
- **Stub fixtures auto-load per test from convention-derived paths** — test bodies never call a stub helper

### 2. `@TestNamespace` (annotation declaring the test class's scope identifier)

```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface TestNamespace {
  String value();
}
```

Usage:
```java
@TestNamespace("datasource-controller")
class DataSourceControllerIntegrationTest extends BaseIntegrationTest { ... }
```

The `value()` is the **top-level directory under `stubs/`** for this class's fixtures. Conventions:
- kebab-case (`datasource-controller`, not `DataSourceController`)
- One annotation per test class, never inherited (each class declares explicitly)
- Generic name (`@TestNamespace`, not `@StubsFor` / `@WireMockFor`) — the value can later scope cache prefixes, log scopes, metric tags, etc. Don't bind the annotation name to one specific use.

### 3. `WireMockStubs` (complete WireMock wrapper: lifecycle + stub loader)

```java
public final class WireMockStubs {
  private static final String FIXTURE_ROOT = "/stubs/";
  private static final String API_MOCK_SUBDIR = "api-mock";
  private static final String FIXTURE_EXTENSION = ".json";

  private final WireMockServer server;
  private final ObjectMapper objectMapper;

  public WireMockStubs() {
    this.server = new WireMockServer(options().dynamicPort());
    this.objectMapper = new ObjectMapper();
  }

  public void start()    { server.start(); }
  public void stop()     { server.stop(); }
  public void resetAll() { server.resetAll(); }
  public int port()      { return server.port(); }
  public String baseUrl(){ return server.baseUrl(); }

  /**
   * Loads every .json file under stubs/{relativeDirPath}/api-mock/.
   * Filenames are free-form; convention is to name after the originating
   * service (connector-request-1.json, gcs-request-1.json, ...).
   * A missing directory is a silent no-op (DB-only tests coexist).
   */
  public void registerAll(String relativeDirPath) {
    String resolvedPath = FIXTURE_ROOT + relativeDirPath + "/" + API_MOCK_SUBDIR;
    URL dirUrl = WireMockStubs.class.getResource(resolvedPath);
    if (dirUrl == null) return;       // silent skip — by design

    Path dir = Paths.get(dirUrl.toURI());
    try (Stream<Path> files = Files.list(dir)) {
      files
        .filter(Files::isRegularFile)
        .filter(p -> p.getFileName().toString().endsWith(FIXTURE_EXTENSION))
        .sorted()
        .forEach(this::registerSingle);
    }
  }

  private void registerSingle(Path fixturePath) {
    JsonNode fixture = objectMapper.readTree(Files.newInputStream(fixturePath));
    MappingBuilder mapping = mappingFor(
        fixture.get("method").asText(), fixture.get("url").asText());

    JsonNode params = fixture.get("params");
    if (params != null && params.isObject()) {
      params.fields().forEachRemaining(e ->
          mapping.withQueryParam(e.getKey(), equalTo(e.getValue().asText())));
    }
    JsonNode request = fixture.get("request");
    if (request != null && !request.isNull()) {
      mapping.withRequestBody(equalToJson(request.toString()));
    }
    ResponseDefinitionBuilder response = aResponse()
        .withStatus(fixture.get("status").asInt())
        .withHeader("Content-Type", "application/json");
    JsonNode responseBody = fixture.get("response");
    if (responseBody != null && !responseBody.isNull()) {
      response.withBody(responseBody.toString());
    }
    server.stubFor(mapping.willReturn(response));
  }
}
```

Design notes:
- **One class owns server + loader** — tests reference `WIRE_MOCK` (singular wrapper), not two separate handles
- **Silent skip on missing directory** — accepted trade-off for "DB-only tests don't need fixture dirs". Drawback: a renamed test that forgets to move its fixture folder fails as "production got 404" rather than "fixture missing"
- **Free-form filenames inside `api-mock/`** — loader doesn't parse filename; just iterates `.json` files sorted alphabetically. Convention to name after originating service: `connector-request-1.json`, `gcs-request-1.json`
- **`api-mock/` subdir partitioning** — leaves room for sibling folders like `db/` (large DB seed payloads) without touching the WireMock loader

### 4. Directory layout (convention-driven, derived from test identity)

```
core/src/test/resources/stubs/
├── datasource-controller/                                ← @TestNamespace value
│   ├── executeRawQuery/                                  ← feature segment of test method
│   │   ├── returnsQueryIdAndPersistsAuditLog/            ← caseExpected segment
│   │   │   └── api-mock/                                 ← WireMock partition
│   │   │       └── connector-request-1.json
│   │   └── whenConnectorFails_persistsAuditLogWithNullRowCount/
│   │       └── api-mock/
│   │           └── connector-request-1.json
│   └── findAllDataSource/
│       └── returnsOnlyCallerGroupSources/
│           └── api-mock/
│               ├── connector-request-1.json              ← connector stub
│               └── gcs-request-1.json                    ← (hypothetical) GCS stub in same test
└── query-controller/
    └── findQueryResultById/
        ├── returnsPagedRows_andTotalFromAuditLog/
        │   └── api-mock/
        │       └── connector-request-1.json
        └── otherGroup_returnsFailure/                    ← no api-mock/ — DB-only test, no stubs
```

Derivation rule for a test method `feature_caseExpected`:
- `feature` = substring before first `_`
- `caseExpected` = substring after first `_` (may contain more `_`)
- Path = `stubs/{annotation.value()}/{feature}/{caseExpected}/api-mock/*.json`

Example: `executeRawQuery_whenConnectorFails_persistsAuditLogWithNullRowCount` →
- `feature` = `executeRawQuery`
- `caseExpected` = `whenConnectorFails_persistsAuditLogWithNullRowCount`
- Path = `stubs/datasource-controller/executeRawQuery/whenConnectorFails_persistsAuditLogWithNullRowCount/api-mock/`

### 5. Fixture file format (the wire contract)

Each fixture defines the entire HTTP interaction:

```json
{
  "url": "/api/connector/executeRawQuery",
  "method": "POST",
  "status": 200,
  "params": { "page": "0", "size": "5" },
  "request": { "sql": "SELECT MONTH, REVENUE FROM REPORTING.MONTHLY" },
  "response": {
    "success": true,
    "result": {
      "columns": [{"name": "MONTH"}, {"name": "REVENUE"}],
      "rows": [["2026-01", 1000], ["2026-02", 2000]],
      "total": 5
    }
  }
}
```

**The Six-Dimension Strict Match** — every dimension is locked:

| Dimension | Why strict-matched |
|-----------|--------------------|
| `url` | Path change in client code surfaces immediately |
| `method` | HTTP method change (POST→GET refactor) surfaces |
| `status` | Wrong-status assumption breaks test |
| `params` | Renamed/dropped query param surfaces |
| `request` body | DTO field rename or Jackson config drift surfaces |
| `response` body | Schema drift on the stub side is caller-visible |

**Why JSON files beat DTO-driven stubs:**

```java
// ❌ DTO-driven stub — wire bytes derived from current Java code
QueryResultResponse stub = new QueryResultResponse(columns, rows, 2);
stubServer.stubFor(post("/api/...").willReturn(okJson(om.writeValueAsString(stub))));
// If someone renames `total` → `rowCount`, both stub and core deserializer
// flip together. Test still passes. Production breaks against the real upstream.

// ✅ JSON fixture — wire bytes pinned to a file
// (auto-loaded by autoRegisterStubs())
// If `total` is renamed, the file still has "total"; core's new
// `rowCount` field deserializes to 0; assertEquals(2, total) fails loudly.
```

The same principle underlies Pact / Spring Cloud Contract — the file *is* the contract.

### 6. `TestFixtures` (entity builders, Object Mother pattern)

```java
public final class TestFixtures {
  public static final String TEST_USERNAME = "test-user";
  public static final String TEST_GROUP_ID = "g-test";
  public static final String OTHER_GROUP_ID = "g-other";

  private TestFixtures() {}

  /** Caller passes {@code connectorPort} so the host:port resolves to the WireMock stub. */
  public static DataSource aDataSourceForGroup(String groupId, String name, int connectorPort) { ... }

  public static UserAccount aUserAccount(String username) { ... }
}
```

Conventions:
- `final class` + private constructor (utility class, never instantiated)
- `a*` / `an*` verbs for builders (Object Mother pattern)
- Tenant constants centralised: `TEST_GROUP_ID`, `OTHER_GROUP_ID`
- Builders return plain Java entities; **do not** persist or call repositories inside fixtures

### 7. Test class (per controller)

```java
@TestNamespace("datasource-controller")
class DataSourceControllerIntegrationTest extends BaseIntegrationTest {

  @Autowired private DataSourceRepository dataSourceRepository;

  // ========== POST /save ==========

  @Test
  void saveDataSource_validRequest_returnsCreatedDataSourceAndPersistsAuditFields() throws Exception {
    Map<String, Object> request = Map.of("name", "test-oracle", ...);

    RestSingleResponse<BasicInfoDTO> response = postApi(
        "/api/data-source/save", request, new TypeReference<>() {});

    assertTrue(response.isSuccess());
    DataSource saved = dataSourceRepository
        .findByGroupIdAndId(TestFixtures.TEST_GROUP_ID, response.getResult().getId())
        .orElseThrow();
    assertEquals(TestFixtures.TEST_GROUP_ID, saved.getGroupId());
    // ... one assertEquals per property
  }

  // ========== POST /executeRawQuery ==========

  @Test
  void executeRawQuery_returnsQueryIdAndPersistsAuditLog() throws Exception {
    // ↑ fixtures under stubs/datasource-controller/executeRawQuery/returnsQueryIdAndPersistsAuditLog/api-mock/
    //   are auto-loaded by @BeforeEach — test body never calls a stub helper

    DataSource dataSource = dataSourceRepository.save(
        TestFixtures.aDataSourceForGroup(..., WIRE_MOCK.port()));

    RestSingleResponse<TrackedQueryResultResponse> response = postApi(...);

    assertTrue(response.isSuccess());
    // ... assertions
  }
}
```

Conventions:
- `@TestNamespace("<kebab-case>")` on the class
- One test class per controller; section dividers `// ========== METHOD /path ==========`
- Test method name: `<feature>_<caseExpected>` — split on first underscore drives auto-load
- Each test exercises **one** behavioural contract — no shared state
- Re-fetch from DB after the API call to verify persisted state (split "API response correctness" from "DB state correctness")
- **Tests don't invoke `stubConnector()` / `stubServer.stubFor(...)`** — fixtures live in resources, loaded by lifecycle

## Flat Assertions (style)

```java
// ❌ Fluent chain — debug unfriendly
assertThat(repository.findByGroupIdAndId(groupId, id))
    .isPresent()
    .get()
    .satisfies(saved -> {
      assertEquals(...);
      assertEquals(...);
    });

// ✅ Flat — failure points at exact line
DataSource saved = repository.findByGroupIdAndId(groupId, id).orElseThrow();
assertEquals(...);
assertEquals(...);
```

When AssertJ *is* the right call:
- Collection contents: `containsExactlyInAnyOrder`, `extracting(::getName).containsExactly(...)`
- Optional emptiness check: `assertThat(opt).isEmpty()` / `.isPresent()` (when not chaining further)
- Cross-cutting collection assertions

Reserve fluent style for collection / cross-cutting assertions; use flat `assertEquals` for single-entity multi-property checks.

## Coverage Patterns (the minimum set per endpoint)

For each tenant-scoped controller endpoint, three test types as a baseline:

| Type | What it locks |
|------|---------------|
| **Happy path** | Endpoint produces the documented contract under normal input |
| **Cross-tenant negative** | Caller from group A cannot read/modify resources of group B; failure messages do not leak existence of foreign resources |
| **Failure / edge case** | Network or dependency failure produces a graceful error; edge cases (missing referenced entity, out-of-range pagination, etc.) do not 500 |

A controller with no cross-tenant test is incomplete coverage — that's the most common production-breaking class of bug for multi-tenant systems.

## The Workflow (per controller)

Apply this exact sequence — don't shortcut steps:

1. **Read the controller** — list endpoints, see request/response DTOs
2. **Read the service** — note tenant scoping (which queries use `groupId`), side effects, cross-store operations
3. **Read entities / DTOs** — flag any `@Deprecated` fields (do not seed or assert them)
4. **Summarise invariants in plain language** — "what business contracts is this endpoint enforcing?"
5. **List a test plan with priority labels** — P0 (must-have), P1 (worth-it), P2 (defer). Wait for sign-off before writing code.
6. **Add `@TestNamespace("<kebab-controller-name>")` to the test class**
7. **Write tests** — one section per HTTP method, follow naming and assertion style above
8. **Add fixtures** — only after confirming the production code path actually reaches the stubbed endpoint (trace from controller through all helper layers). Place under `stubs/<ns>/<feature>/<case>/api-mock/`
9. **Run `mvn test`** — every test must pass before commit
10. **Run audit greps** (see below)
11. **Commit with conventional message** — `test(module): cover <Controller>` style

## Pre-Commit Audit Greps

```bash
# 1. No `findById(` in test code — use `findByGroupIdAndId` for tenant scope
grep -rn 'findById(' src/test/

# 2. No `.satisfies(` chain in test files
grep -rn '\.satisfies(' src/test/

# 3. No deprecated entity setters seeded in tests/fixtures (adjust list)
grep -rnE 'setSpaceIds|setColumns|setRows' src/test/

# 4. Every IntegrationTest class declares @TestNamespace
for f in $(find src/test -name '*IntegrationTest.java'); do
  grep -l '@TestNamespace' "$f" >/dev/null || echo "MISSING @TestNamespace: $f"
done

# 5. Every fixture lives under api-mock/ subdirectory
find src/test/resources/stubs -name '*.json' \
  | grep -v '/api-mock/' \
  && echo "Fixtures found outside api-mock/ partition"

# 6. Test method name follows feature_caseExpected (has underscore)
grep -rnP 'void [a-zA-Z]+\(\)' src/test/ \
  | grep -vP 'void \w+_\w+' \
  | grep -v 'setUp\|tearDown\|cleanMongo\|cleanPostgres'

# 7. All fixture JSON files have required keys
for f in $(find src/test/resources/stubs -name '*.json'); do
  python3 -c "import json; d=json.load(open('$f')); missing=set(['url','method','status']) - set(d); print('$f', 'missing:', missing) if missing else None"
done
```

## Anti-Patterns to Avoid

### Adding a stub fixture without tracing the production call path

```
# ❌ Just drop a JSON in api-mock/ and hope it's consumed
stubs/my-controller/foo/bar/api-mock/connector-request-1.json

# Verify first: from the controller method, follow every service / helper /
# response-builder call. If the stubbed endpoint is never invoked, the
# fixture is dead. If you remove a fixture you assumed was dead but a
# 5-level-deep helper calls it, the test will fail — that failure is your
# only signal that the production path actually depends on the stub.
```

### Renaming a test method without moving its fixture directory

The auto-loader silently skips missing directories. Renaming `foo_bar` → `foo_baz` without renaming the folder leaves the new test with no stubs → production code makes a real HTTP call → WireMock 404 → test fails with a confusing "response success=false" message rather than a clear "fixture missing" error. **Rename test method and fixture directory in the same commit.**

### Seeding deprecated entity fields

If an entity has `@Deprecated private List<String> spaceIds;`, the test must not call `setSpaceIds(...)`. Tests that lock deprecated fields delay the deprecation indefinitely.

### Multi-storage operations without rollback awareness

If a service touches Mongo *and* Postgres in the same method, `@Transactional` only covers JPA. A failure mid-operation can leave partial Mongo writes that don't roll back. The test should either:
- Cover the failure path explicitly and assert the partial-write behaviour, **or**
- Flag the cross-store rollback gap to the team — don't paper over it with a stub

### Using fluent `.satisfies(lambda)` for multi-property assertions

```java
// ❌
assertThat(opt).isPresent().get().satisfies(x -> {
  assertEquals(...);
  assertEquals(...);
});

// Failure trace points at AssertJ wrapper, not the specific assertEquals line.
// Re-running with -X to get the inner stack is debug overhead per failure.
```

### Treating the wire contract as "whatever Jackson produces from our DTO"

The wire is a public contract with the other service. Pin it to a file. Let DTO refactors break tests so the contract change becomes a conscious decision rather than a silent drift.

### Calling stub setup from test bodies

```java
// ❌ Old pattern — explicit per-test stub call
@Test
void foo_bar() {
  stubConnector();   // boilerplate
  // ...
}

// ✅ New pattern — fixture in resources, auto-loaded by @BeforeEach
@Test
void foo_bar() {
  // fixture at stubs/<ns>/foo/bar/api-mock/*.json was already loaded
  // ...
}
```

Test bodies stay focused on arrange / act / assert. Stub registration is lifecycle, not logic.

## Industry Positioning

Where this pattern sits in the integration-test sophistication spectrum:

| Level | Description | Tools / examples | Typical adopter |
|-------|-------------|------------------|-----------------|
| **L1** | Inline stubs (`stubFor(...)` in test body) | Most WireMock tutorials | ~70% of WireMock users |
| **L2** | Helper methods abstract common stubs | Custom `TestHelpers.stubX(...)` | Mid-size projects with DRY discipline |
| **L3** | External JSON fixtures with helper loader | Flat directory, `loadFixture("foo.json")` | Disciplined teams |
| **L4** | **Convention-driven directory layout, auto-load** | **This pattern**, Approval Testing, VCR cassettes, Pytest snapshots | Teams that invested in test infra |
| **L5** | Contract testing with broker | Pact, Spring Cloud Contract | Heavy microservice environments, cross-team |
| **L6** | Service virtualization platform | Hoverfly, Mountebank, internal tools | FAANG, finance |

This pattern's value-vs-cost trade-off:

- **Above L1-L2**: Worth investing once you have 5+ controllers and a stable upstream service. Pays off in: rename safety, contract drift detection, test code stays small as suite grows.
- **Below L5**: Skip this for single-team / small-suite projects (overkill) AND for cross-team contract scenarios where Pact's broker / provider verification is what you actually need.
- **Sweet spot**: Small-to-mid SaaS, 3-15 controllers, stable upstream HTTP service, team has discipline to follow naming conventions.

Comparable patterns in other ecosystems (this design borrows from them):

| Tool | What it shares with this pattern |
|------|----------------------------------|
| **Approval Testing** (Java `Approvals`) | Snapshot named after JUnit method, auto-derived path |
| **VCR / vcrpy** (Ruby/Python) | HTTP cassette named after test, auto-load via decorator/annotation |
| **Pytest snapshot** | `__snapshots__/{test_name}/` directory, zero-arg API |
| **Spring Cloud Contract** | Directory convention tied to test class location |

The novelty is the combination: WireMock + JSON fixtures + auto-derive from JUnit `TestInfo` + `@TestNamespace` annotation + `api-mock/` partitioning. Each piece is standard; the assembly is what makes this pattern useful.

## When the Test Catches You

The integration test suite is a feedback channel as much as a regression net. Real cases:

| What I changed (wrong) | Test signal | Why the signal mattered |
|-----------------------|-------------|-------------------------|
| Removed a "dead" stub fixture | Test failed at controller layer | Confirmed the stub *was* consumed via a 5-level-deep helper |
| Renamed a DTO field | Fixture didn't auto-update → test failed loudly | Caught what DTO-driven round-trip stubs would have hidden |
| Renamed test method without moving fixture dir | Silent skip → production 404 | Forced the rename-both-together discipline |
| Added retry logic to client | Test still passed (persist stubs + reset between) | Reminder: use `verify(exactly(1), ...)` when call-count matters |

Pay attention to these failures — they are the system's way of telling you the spec drifted. The cheapest moment to fix a contract change is when the integration test fails locally.

## Evolution: Iterative Refinement

This pattern evolved through multiple PR review cycles. Notable iterations:

1. **v0**: `ConnectorStubs.stubFromFixture(server, "name.json")` — flat directory, explicit per-test call
2. **v1**: Convention-driven path → `stubs/{ns}/{feature}/{case}/connector-request-N.json`, but still explicit `stubConnector()` call
3. **v2**: Auto-register in `@BeforeEach` via JUnit `TestInfo` — test bodies stop calling stub helpers
4. **v3**: `WireMockStubs` wrapper owns server lifecycle + stub loading (one class, not two)
5. **v4**: `api-mock/` subdirectory partition — leaves room for `db/`, `event-mock/`, other fixture types per test

Lesson: don't try to land v4 in one PR. Land v0, get review feedback, iterate. Each iteration tightened one design dimension at a time. The final shape was not predictable from the start — it emerged from reviewer feedback (which is L4 design hallmark: convention discovered, not pre-engineered).

## Bottom Line

Spring Boot integration tests are worth setting up properly **once** per module:

1. Single `BaseIntegrationTest` extending Testcontainers + WireMock + MockMvc
2. `@TestNamespace` annotation declaring per-class scope
3. `WireMockStubs` wrapper owning server lifecycle + stub loading
4. JSON fixtures under `stubs/{ns}/{feature}/{case}/api-mock/` — auto-loaded by lifecycle
5. `TestFixtures` for entity builders (Object Mother)
6. Flat assertions, one per property
7. Mandatory cross-tenant negative case per tenant-scoped endpoint
8. Trace production paths before adding or removing a fixture

When this set is in place, adding tests for a new controller is a 30-minute repeat:
1. Add new test class with `@TestNamespace("<controller>")`
2. Write test methods following `<feature>_<caseExpected>` convention
3. Drop fixtures into `stubs/<ns>/<feature>/<case>/api-mock/`
4. Run tests

When it is not, every controller test ends up reinventing infrastructure and the suite becomes inconsistent.
