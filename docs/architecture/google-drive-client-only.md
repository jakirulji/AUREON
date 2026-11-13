# ADR: Google Drive client-only access

- Status: Accepted for implementation planning
- Date: 2026-11-14
- Scope: Google Drive integration for the public AUREON Android app, with Windows later

## Context

AUREON is intended for public multi-user use and needs access to users' existing
Google Drive libraries. The broad Drive `drive` scope is Restricted. Google
requires OAuth verification for public apps using Restricted scopes and an
annual independent security assessment when the app stores/transmits restricted
Drive data on servers or can access it from/through a third-party server.

The previous proposed flow sent refresh credentials to each user's Cloudflare
Worker. That design creates a server-side restricted-data assessment trigger
and is incompatible with the user's zero-cost constraint.

## Decision

Google Drive authorization, API calls, file content, and all Drive-derived
metadata remain on the user's device.

- Android uses Google's Android AuthorizationClient / supported Android
  authorization APIs. It requests on-device access tokens and calls Drive API
  directly.
- Windows later uses a native Desktop OAuth client and installed-app flow with
  an external browser and PKCE; token exchange stays inside the Windows client.
- No Google auth code, access token, refresh token, Drive file content, or
  Drive-derived metadata is sent to the AUREON backend or personal Worker.
- The Cloudflare Worker remains limited to AUREON account/backend data that is
  not sourced from Google Drive.
- Each device independently authorizes its Google account. Google tokens are
  not restored through the AUREON account.
- Portable Drive-derived metadata backups, if implemented, are user-controlled
  encrypted files and are not synchronized to the AUREON Worker.

## Scope decision

The required full-library read/write behavior needs
`https://www.googleapis.com/auth/drive`. The `drive.file` scope does not expose
the user's entire pre-existing Drive library; `drive.readonly` cannot support
writes. Request only `drive` if the product continues to require all listed
read/write/manage operations. Do not add redundant scopes.

## Consequences

### Benefits

- Removes AUREON's third-party server from the Google Drive data path.
- Avoids storing Google refresh tokens in Cloudflare D1 or a central vault.
- Makes the design eligible to ask Google to confirm that the server-side CASA
  assessment trigger does not apply.

### Trade-offs

- Every device must obtain its own Google authorization.
- Cross-device automatic restoration of Drive tokens is intentionally removed.
- Drive-derived indexes and folder mappings cannot be synchronized through the
  AUREON Worker. A user-controlled export/import file is the planned fallback.
- Restricted Scope OAuth verification is still required for a public app.
- No guarantee of zero cost exists until Google confirms the final assessment
  requirements. The architecture alone does not grant an exemption.

## Release gates

1. Implement Android native authorization and direct Drive API access.
2. Prove by tests/log review that no Google tokens or Drive-derived data leave
   the device for AUREON-controlled servers.
3. Implement revoke/disconnect and local credential cleanup.
4. Update the public Privacy Policy to match the actual implementation.
5. Submit the complete demo and scope justification to Google's verification
   process; obtain written confirmation of security-assessment applicability
   before assuming CASA fees are avoided.
