# AUREON Backend Spike

This is a disposable A0 architecture spike, **not a production backend**.

## Current scope

- Ktor 3.6.1 / Kotlin 2.4.21 / JDK 21.
- Modular-monolith starting point.
- Public liveness endpoint.
- Protected sample route with an injected session-authentication boundary.
- Deny-all default authenticator: no real Master Account login, JWT issuer, device-key verification or provider OAuth exchange is implemented. PostgreSQL is used only for the tested lease/outbox persistence spike.
- A KMS data-key port with a test proving KMS failure blocks the credential operation and zeroes the plaintext test key after use. It does not implement cryptography or connect to a real KMS.
- PostgreSQL/HikariCP pool and a real PostgreSQL compare-and-swap refresh-lease repository with a concurrent two-worker race test.
- PostgreSQL outbox leasing, stale-lease completion protection and retry/reschedule tests.
- OAuth PKCE S256, state-hash and exact redirect-allowlist primitives. No provider authorization-code exchange is implemented.
- Tests prove that missing/invalid credentials are rejected and a test-only injected authenticator can authorize a request.

## Run

Requires JDK 21 and Gradle 9.9.0 or compatible newer version.

```bash
cd backend
gradle :server:test
gradle :server:run
```

Then request:

- `GET http://localhost:8080/health/live`
- `GET http://localhost:8080/v1/me` (401 until a real server-side authenticator is implemented)

## Security boundary

Do not add real secrets, production credentials, provider tokens, KMS key material or user data to this spike. The test token exists only inside an isolated unit test. Production authentication must use server-issued revocable sessions bound to registered devices. Credential-vault encryption, a real KMS adapter, provider authorization-code exchange, device-key verification and a production outbox handler are deliberately not represented as complete here. PostgreSQL lease/outbox persistence is a tested spike, not a production service.

## Exit status

This spike validates Ktor HTTP/authentication boundaries, PostgreSQL 18 connectivity and selected lease/outbox transactions, OAuth PKCE primitives and a fake KMS boundary. It does **not** close the full ADR-0001 architecture spike or A0.
