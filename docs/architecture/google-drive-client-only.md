# ADR: Google Drive client-only access

- Status: Accepted for implementation planning
- Date: 2026-11-14
- Scope: Google Drive integration for the public AUREON Android app, with Windows later

## Context

AUREON is intended for public multi-user use and needs access to users' existing Google Drive libraries. The broad Drive `drive` scope is Restricted. Google requires OAuth verification for public apps using Restricted scopes and an annual independent security assessment when the app stores/transmits restricted Drive data on servers or can access it from/through a third-party server.

The previous proposed flow sent refresh credentials to each user's Cloudflare Worker. That design creates a server-side restricted-data assessment trigger and is incompatible with the user's zero-cost constraint.

## Decision

Google Drive authorization, API calls, file content, and all Drive-derived metadata remain on the user's device.

- Android uses Google's Android AuthorizationClient / supported Android authorization APIs. It requests on-device access tokens and calls Drive API directly.
- Windows later uses a native Desktop OAuth client and installed-app flow with an external browser and PKCE; token exchange stays inside the Windows client.
- No Google auth code, access token, refresh token, Drive file content, or Drive-derived metadata is sent to the AUREON backend or personal Worker.
- The Cloudflare Worker remains limited to AUREON account/backend data that is not sourced from Google Drive.
- Each device independently authorizes its Google account. Google tokens are not restored through the AUREON account.

## Master Account-assisted restoration

AUREON should restore as much setup as possible after the user signs in to the same Master Account on a new device, without moving Google Drive data or credentials to a server.

- The Master Account backend may store a minimal user-managed connection-slot registry: slot IDs, user-chosen labels (for example, "Personal Drive" or "Archive"), display order, and whether a slot is configured. These values must be entered/managed by the user and must not be populated from Drive API responses.
- Do not store Google email addresses, Google account IDs, OAuth grants, auth codes, access/refresh tokens, Drive file IDs, file names, folder hierarchy, file-to-account mappings, or any other Drive-derived information in the Master Account backend unless Google explicitly confirms that the proposed data handling is permitted.
- On a new device, AUREON restores the user's connection slots and prompts the user to authorize the corresponding Google account(s) locally. The user chooses the account in Google's authorization UI and confirms which restored slot it belongs to. This is guided reconnection, not silent token transfer.
- Drive-derived virtual folder structure, indexes, and file-to-account mappings remain local. To migrate those, provide a user-controlled encrypted export/import recovery package that is transferred by the user (for example, via USB or their own file storage), not uploaded to the AUREON Worker.
- Cloud sync of even client-encrypted Drive-derived metadata is not approved by this ADR. Encryption alone must not be treated as a policy exemption. Revisit only after written Google policy/verification guidance.

## Scope decision

The required full-library read/write behavior needs `https://www.googleapis.com/auth/drive`. The `drive.file` scope does not expose the user's entire pre-existing Drive library; `drive.readonly` is read-only; `drive` scope is needed for full read/write/manage. Request only `drive` if the product continues to require all listed read/write/manage operations.

## Consequences

### Benefits

- Removes AUREON's third-party server from the Google Drive data path.
- Avoids storing Google refresh tokens in Cloudflare D1 or a central vault.
- Allows Master Account to restore user-defined connection slots and guide account reconnection.
- Makes the design eligible to ask Google to confirm that the server-side CASA assessment trigger does not apply.

### Trade-offs

- Every device must obtain its own Google authorization; there is no silent token restore.
- Restored connection slots do not prove that the same Google account was reconnected; the user must confirm it.
- Drive-derived indexes and folder mappings cannot be synchronized through the AUREON Worker. A user-controlled export/import file is the planned fallback.
- Restricted Scope OAuth verification is still required for a public app.
- No guarantee of zero cost exists until Google confirms the final assessment requirements. The architecture alone does not grant an exemption.

## Release gates

1. Implement Android native authorization and direct Drive API access.
2. Implement Master Account restoration of user-defined connection slots only; validate that no Google-derived data is written to the backend.
3. Provide encrypted local export/import for Drive-derived metadata and test recovery on a clean device.
4. Prove by tests/log review that no Google tokens or Drive-derived data leave the device for AUREON-controlled servers.
5. Implement revoke/disconnect and local credential cleanup.
6. Update the public Privacy Policy to match the actual implementation.
7. Submit the complete demo and scope justification to Google's verification process; obtain written confirmation of security-assessment applicability before assuming CASA fees are avoided.
