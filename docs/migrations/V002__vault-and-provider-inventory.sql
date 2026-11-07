-- AUREON additive PostgreSQL migration
-- Migration: V002__vault-and-provider-inventory.sql
-- Requires V001__initial_schema.sql. Never edit V001 after it has shipped.
-- Draft only: run via CI against PostgreSQL 16 and review before production.
-- No plaintext OAuth tokens, authorization codes, PKCE verifiers or KMS key material are stored.

BEGIN;

-- Google Photos is a distinct provider surface; it is not Google Drive folders.
ALTER TABLE provider_accounts
    DROP CONSTRAINT provider_accounts_provider_check;
ALTER TABLE provider_accounts
    ADD CONSTRAINT provider_accounts_provider_check
    CHECK (provider IN (
        'google_drive', 'google_photos', 'onedrive', 'dropbox',
        's3_compatible', 'other'
    ));

-- Credential envelope metadata and concurrency control.
ALTER TABLE provider_credentials
    ADD COLUMN encryption_algorithm text NOT NULL DEFAULT 'AES-256-GCM'
        CHECK (encryption_algorithm IN ('AES-256-GCM', 'AES-128-GCM', 'other-reviewed')),
    ADD COLUMN credential_version bigint NOT NULL DEFAULT 1
        CHECK (credential_version > 0),
    ADD COLUMN credential_status text NOT NULL DEFAULT 'active'
        CHECK (credential_status IN ('active', 'refreshing', 'reauth_required', 'revocation_pending', 'revoked', 'vault_unavailable')),
    ADD COLUMN consented_at timestamptz,
    ADD COLUMN last_refresh_attempt_at timestamptz,
    ADD COLUMN last_refresh_success_at timestamptz,
    ADD COLUMN refresh_lease_id uuid,
    ADD COLUMN refresh_lease_expires_at timestamptz,
    ADD COLUMN last_error_code text,
    ADD COLUMN created_at timestamptz NOT NULL DEFAULT now(),
    ADD CONSTRAINT ck_provider_credentials_refresh_lease
        CHECK ((refresh_lease_id IS NULL) = (refresh_lease_expires_at IS NULL)),
    ADD CONSTRAINT ck_provider_credentials_refreshing_lease
        CHECK (credential_status <> 'refreshing' OR refresh_lease_id IS NOT NULL);

CREATE INDEX ix_provider_credentials_refresh_lease
    ON provider_credentials(refresh_lease_expires_at)
    WHERE refresh_lease_id IS NOT NULL;

COMMENT ON COLUMN provider_credentials.encrypted_refresh_envelope IS
    'Versioned authenticated-encryption envelope; includes wrapped DEK, nonce, ciphertext and tag. Never plaintext.';
COMMENT ON COLUMN provider_credentials.kms_key_reference IS
    'Non-secret managed KMS/HSM key identifier; never raw key material.';
COMMENT ON COLUMN provider_credentials.credential_version IS
    'Optimistic concurrency/CAS version. Increment atomically whenever the encrypted refresh credential changes.';

-- Short-lived OAuth transaction. Raw state is not stored; only its SHA-256 hash.
-- PKCE verifier is nullable because callback/exchange mode is provider-specific.
CREATE TABLE provider_oauth_transactions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    device_id           uuid NOT NULL,
    provider            text NOT NULL CHECK (provider IN (
                            'google_drive', 'google_photos', 'onedrive',
                            'dropbox', 's3_compatible', 'other'
                        )),
    state_sha256        bytea NOT NULL CHECK (octet_length(state_sha256) = 32),
    pkce_verifier_envelope bytea,
    pkce_challenge_sha256 bytea NOT NULL CHECK (octet_length(pkce_challenge_sha256) = 32),
    callback_mode       text NOT NULL CHECK (callback_mode IN ('backend_https', 'native_app')),
    redirect_uri        text NOT NULL,
    requested_scopes    text[] NOT NULL DEFAULT '{}',
    status              text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'exchanging', 'completed', 'cancelled', 'failed', 'expired')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,
    consumed_at         timestamptz,
    completed_provider_account_id uuid,
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    FOREIGN KEY (user_id, device_id) REFERENCES devices(user_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, completed_provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    UNIQUE (state_sha256),
    CHECK (expires_at > created_at),
    CHECK ((status = 'pending') = (consumed_at IS NULL)),
    CHECK (status <> 'completed' OR completed_provider_account_id IS NOT NULL),
    CHECK (status = 'completed' OR completed_provider_account_id IS NULL),
    CHECK (callback_mode <> 'backend_https' OR pkce_verifier_envelope IS NOT NULL)
);
CREATE INDEX ix_provider_oauth_transactions_expiry
    ON provider_oauth_transactions(expires_at)
    WHERE status IN ('pending', 'exchanging');

-- One account-wide cursor per resource scope, independent of device. Page/change
-- tokens are opaque and encrypted; no provider cursor is written to logs.
CREATE TABLE provider_inventory_cursors (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    scope_key           text NOT NULL DEFAULT 'root',
    page_cursor_envelope bytea,
    change_cursor_envelope bytea,
    initial_scan_state  text NOT NULL DEFAULT 'not_started'
                        CHECK (initial_scan_state IN ('not_started', 'running', 'completed', 'blocked', 'failed')),
    initial_scan_started_at timestamptz,
    initial_scan_completed_at timestamptz,
    last_incremental_sync_at timestamptz,
    last_error_code     text,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    FOREIGN KEY (user_id, provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, provider_account_id, scope_key),
    CHECK (initial_scan_state <> 'completed' OR initial_scan_completed_at IS NOT NULL)
);
CREATE INDEX ix_provider_inventory_cursors_account
    ON provider_inventory_cursors(user_id, provider_account_id, updated_at DESC);

-- Provider-native inventory. Names/paths/metadata are encrypted in the envelope;
-- structural IDs and MIME type remain visible for hierarchy and virtual categories.
CREATE TABLE provider_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    provider_item_id    text NOT NULL,
    parent_provider_item_id text,
    item_kind           text NOT NULL CHECK (item_kind IN (
                            'file', 'folder', 'shortcut', 'shared_file',
                            'shared_folder', 'unknown'
                        )),
    mime_type           text,
    metadata_envelope   bytea NOT NULL,
    metadata_format_version integer NOT NULL CHECK (metadata_format_version > 0),
    size_bytes          bigint CHECK (size_bytes IS NULL OR size_bytes >= 0),
    provider_modified_at timestamptz,
    provider_version_tag text,
    shortcut_target_provider_item_id text,
    is_trashed          boolean NOT NULL DEFAULT false,
    is_orphaned         boolean NOT NULL DEFAULT false,
    first_seen_at       timestamptz NOT NULL DEFAULT now(),
    last_seen_at        timestamptz NOT NULL DEFAULT now(),
    provider_deleted_at timestamptz,
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    FOREIGN KEY (user_id, provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, provider_account_id, provider_item_id),
    CHECK (item_kind <> 'shortcut' OR shortcut_target_provider_item_id IS NOT NULL)
);
CREATE INDEX ix_provider_items_parent
    ON provider_items(user_id, provider_account_id, parent_provider_item_id);
CREATE INDEX ix_provider_items_category
    ON provider_items(user_id, provider_account_id, mime_type)
    WHERE is_trashed = false;
CREATE INDEX ix_provider_items_modified
    ON provider_items(user_id, provider_account_id, provider_modified_at DESC);

-- Provider-native albums are separate from filesystem folders. Populate only
-- where the provider API exposes album metadata/membership to the granted scope.
CREATE TABLE provider_albums (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    provider_album_id   text NOT NULL,
    metadata_envelope   bytea NOT NULL,
    metadata_format_version integer NOT NULL CHECK (metadata_format_version > 0),
    provider_modified_at timestamptz,
    first_seen_at       timestamptz NOT NULL DEFAULT now(),
    last_seen_at        timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, provider_account_id, provider_album_id),
    UNIQUE (user_id, provider_account_id, id)
);

CREATE TABLE provider_album_memberships (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    album_id            uuid NOT NULL,
    provider_media_item_id text NOT NULL,
    added_at            timestamptz,
    FOREIGN KEY (user_id, provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, provider_account_id, album_id)
        REFERENCES provider_albums(user_id, provider_account_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, provider_account_id, album_id, provider_media_item_id)
);

COMMIT;

-- Application/service responsibilities:
-- * Generate and validate state/PKCE using a reviewed CSPRNG and RFC-compliant implementation.
-- * Never persist raw authorization codes or provider access tokens.
-- * Expire and delete consumed OAuth transaction secrets according to a short retention policy.
-- * KMS-wrap credential envelope DEKs; enforce a dedicated broker identity and audit every decrypt.
-- * Acquire/renew/release refresh leases transactionally and compare-and-swap credential_version.
-- * A stale refresh worker must never overwrite a newer rotated credential.
-- * Page inventory resumably; preserve actual parent IDs; never move/rename/delete provider originals.
-- * Mark orphaned items only after a complete authoritative scan proves the parent is missing.
-- * Treat Photos albums as albums, not Drive folders; store only API-exposed memberships.
-- * No schema row authorizes local-original deletion or remote-object deletion.
