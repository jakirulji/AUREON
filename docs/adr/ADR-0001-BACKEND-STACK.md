# ADR-0001 — Backend Technology and Runtime

**Status:** Provisional recommendation; basic Ktor scaffold passed CI, full architecture spike remains open  
**Date:** 2026-11-07  
**Decision owner:** AUREON project  
**Scope:** Android-first AUREON control-plane backend; Windows client remains a later phase

## Context

AUREON needs a secure control plane for Master Account sessions, device registry, provider OAuth transactions, a user-consented credential vault, provider inventory, file metadata, sync cursors, transfer coordination, audit events and background outbox workers.

The backend is not intended to proxy all file bytes. Direct client-to-provider transfer remains preferred where provider APIs permit it. The backend must nevertheless issue short-lived access tokens to authenticated native adapters where direct provider API calls require bearer authorization; refresh credentials stay in the server-side vault.

The first release should be a modular monolith, not a distributed microservice fleet. A single deployable reduces operational burden while modules preserve boundaries around identity, credential vault, provider adapters, inventory, files and transfers.

## Options considered

| Option | Strengths | Costs / risks | AUREON fit |
|---|---|---|---|
| Kotlin + Ktor | Kotlin/JVM compatibility; coroutine-oriented server; explicit routing and plugins; shares language/tooling familiarity with Android Kotlin | Less batteries-included than Spring; security, transaction and module conventions must be deliberately designed | **Best initial fit** |
| Kotlin + Spring Boot | Mature production ecosystem, extensive integrations and conventions, strong Kotlin support | More framework surface and operational/runtime weight than the MVP needs; more conventions to learn and maintain | Strong fallback if Ktor spike reveals missing integrations |
| Go + net/http/pgx | Lean runtime, strong standard HTTP/database foundations, simple deployment | Adds a second primary backend language and separate model/tooling from Android Kotlin | Technically strong, but no decisive MVP advantage |

Ktor's server Authentication plugin supports bearer/JWT and custom authentication providers. Its OpenID Connect plugin is documented as experimental/JVM-only, so AUREON must not make that experimental plugin a security-critical dependency; use provider-specific reviewed OAuth/OIDC libraries or explicit protocol handling instead. Kotlin is interoperable with the Java ecosystem. Spring Boot is a mature alternative, while Go's standard `database/sql` supports PostgreSQL through drivers.

## Recommendation

Use **Kotlin 2.4.21 / JVM 21 + Ktor 3.6.1** as the provisional backend stack, deployed as a modular monolith.

Initial supporting choices:

- **Runtime:** JDK 21 LTS baseline. Pin JDK 21, Kotlin 2.4.21, Gradle 9.9.0 and Ktor 3.6.1 in CI for this spike; re-evaluate patch updates through dependency review.
- **HTTP/API:** Ktor Server, typed request/response models, kotlinx.serialization, explicit validation and centralized error mapping.
- **Authentication:** Ktor Authentication plugin for AUREON session bearer verification and device binding. Master Account authentication is separate from provider OAuth.
- **Database:** PostgreSQL 18 for the initial control plane; this matches the current CI service target.
- **Database access:** HikariCP + JDBC with explicit SQL repositories for the first implementation. Keep blocking JDBC work off Ktor event-loop threads using a bounded IO execution boundary.
- **Migrations:** Flyway or an equivalent ordered migration runner. Preserve V001 and apply V002 additively; never mutate an already-applied migration.
- **Background work:** database-backed outbox/lease worker in the same deployable initially. Do not add a message broker until measured need exists.
- **Provider integration:** provider-specific adapters behind a narrow interface; credential broker is a separate module and only component allowed to decrypt provider refresh-token envelopes.
- **KMS:** provider-neutral KMS interface with a fake/local test implementation for tests; production KMS vendor/region remains an external deployment decision.
- **Testing:** Ktor `testApplication`, unit tests, PostgreSQL integration tests using a disposable database/Testcontainers, OAuth callback/PKCE tests, refresh-rotation concurrency tests and fault-injection tests.
- **Deployment:** OCI container. Hosting provider, region, domain, backups and cost ceiling remain undecided and must be approved before production data is stored.

Do not use Ktor's experimental OIDC plugin as a substitute for explicit provider security review. Do not implement custom cryptography. Use a reviewed AEAD/KMS envelope design from the separate E2E and credential-vault specifications.

## Why this is the best starting point

1. **Language continuity:** Android's native integration is Kotlin. Kotlin on the server reduces language/tooling fragmentation and allows shared protocol types only where that does not couple UI/domain logic.
2. **Appropriate complexity:** Ktor provides the HTTP/auth foundation without requiring a microservice or large framework architecture for an early product.
3. **Explicit security boundaries:** a modular monolith can isolate credential-vault decryption from ordinary API, inventory and transfer modules.
4. **SQL transparency:** the current schema has important composite ownership constraints, leases and idempotency rules. Explicit SQL plus migrations makes those behaviors visible and testable.
5. **Reversibility:** if the spike shows that Ktor lacks a required maintained integration, Spring Boot remains a low-friction Kotlin/JVM fallback. Avoid prematurely committing to Go or microservices.

## Required architecture spike before marking the stack verified

Build a disposable proof-of-concept, not the production app, that demonstrates:

1. Ktor starts with health/readiness routes and structured redacted request logging.
2. AUREON bearer session validation and device binding protect a sample route.
3. PostgreSQL 16 connects through a bounded pool.
4. Flyway applies V001 then V002 to a clean database; a second startup is safe and does not reapply migrations.
5. The V001 and V002 smoke tests pass against PostgreSQL 16.
6. One OAuth start/callback transaction validates state, PKCE and one-time consumption without logging code/verifier.
7. A fake KMS implementation exercises envelope encrypt/decrypt, consent gating, refresh lease and compare-and-swap rotation. Production KMS credentials are not used in the spike.
8. A simulated concurrent refresh test proves only one effective rotation can commit.
9. An outbox worker claims, leases, retries and completes a test event without processing secrets.
10. Container build and CI tests complete reproducibly.

### Acceptance gates

- No secrets in source, repository, test fixtures or logs.
- Cross-user database references fail.
- KMS failure fails closed.
- Migration rerun is safe under the chosen migration runner.
- No raw provider refresh token is returned to a client.
- Short-lived access token is returned only to the native provider adapter through the dedicated broker contract.
- No file-content key enters the backend vault.
- A clean disposable environment can reproduce the test suite.

If any critical gate fails, revise the stack decision before A1 production implementation.

## Current spike evidence

- Backend scaffold CI run #42370407442: JDK 21 setup, Gradle 9.9.0 setup, Ktor compile, four HTTP/authentication tests and backend build all passed.
- Extended fake-KMS and refresh-lease tests passed in GitHub Actions run #42370500985.
- No PostgreSQL connection, Flyway migration runner, production authentication, real KMS SDK, OAuth provider, outbox worker or container image has been implemented in the spike.

## Consequences

### Positive
- One primary backend language shared with Android native work.
- Clear module boundaries without early distributed-system complexity.
- PostgreSQL schema and API contracts remain technology-neutral.
- Explicit provider-vault isolation is possible within one deployable.

### Negative / accepted tradeoffs
- The team must define conventions for dependency injection, module boundaries, database transactions and background workers.
- JDBC is blocking; all repository calls must use a bounded IO executor and must not block event-loop threads.
- Ktor offers less out-of-the-box operational convention than Spring Boot; observability, metrics, rate limiting and security headers must be intentionally configured.
- Kotlin/JVM runtime footprint may be larger than Go; optimize only after representative measurements.

## References

- [Ktor Server documentation](https://ktor.io/docs/ktor-server.html)
- [Ktor Authentication and Authorization](https://ktor.io/docs/server-auth.html)
- [Ktor 3.6.0 release announcement, 18 September 2026](https://blog.jetbrains.com/ktor/2026/09/18/ktor-3-6-0-is-now-available/)
- [Kotlin server-side development overview](https://kotlinlang.org/docs/server-overview.html)
- [Spring Boot system requirements](https://docs.spring.io/spring-boot/system-requirements.html)
- [Go database access](https://go.dev/doc/database/)

