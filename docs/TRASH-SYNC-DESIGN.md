# AUREON — Provider-backed Trash Sync Design

**Status:** Contract and database foundation; live service/client integration pending.

## Scope

Cross-device Trash synchronization applies only to files already represented by a linked cloud provider account and stable provider item ID. It does not apply to arbitrary local files selected through Android SAF or Windows filesystem browsing.

## Lifecycle

1. A provider adapter performs the provider-native Trash operation or moves the object into an AUREON-managed folder within that same provider account.
2. The adapter confirms the provider outcome.
3. The client records the Trash lifecycle with a unique operation ID. Retries with the same operation ID must return the same record.
4. Other signed-in devices list the account's active Trash records and resolve display names from provider inventory.
5. Restore or permanent deletion is performed by the provider adapter first. Only after provider confirmation does the client commit the metadata state transition with the expected row version and a new operation ID.
6. Devices reconcile by cursor/row version. Stale transitions return conflict and require refresh; they must not silently overwrite a newer state.

## Data boundary

The server stores provider account/item IDs, original parent ID, Trash mode/container ID, state, timestamps, device provenance and row version. It does not store file bytes, local absolute paths, SAF tree URIs, content:// URIs, OAuth credentials or plaintext content keys. Display names are resolved from provider inventory.

## Local-only Trash

A selected local directory root is scoped to the device/OS grant. Its child IDs may be SAF document IDs or Win32 paths and are not portable to another device. Such entries remain in local Trash and must never be uploaded as if they were cloud objects. A future provider-linked Files model can opt into cross-device Trash when it can supply a stable providerAccountId and providerItemId.

## Safety

- Metadata endpoints never perform provider operations or delete content.
- The client records only provider-confirmed outcomes.
- Permanent deletion requires separate explicit user confirmation and provider confirmation.
- Provider retention/expiry remains authoritative.
- A disconnected or reauth-required account keeps its Trash metadata visible as stale; restore/purge is blocked until provider authorization is available.
- No local original is deleted by metadata sync.

## Delivery boundary

V003 and OpenAPI are validated by CI. They do not make Trash sync operational until authenticated Ktor routes, PostgreSQL repository methods, provider adapters, app account/session integration, and multi-device conflict/retry tests are implemented.
