-- AUREON PostgreSQL baseline migration
-- Migration: V001__initial_schema.sql
-- Status: A0 proposed draft; validate on the selected PostgreSQL major version.
-- This schema stores control-plane metadata only, not file bytes or plaintext content keys.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    normalized_login_identifier text,
    status              text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'active', 'suspended', 'deletion_pending', 'deleted')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);
CREATE UNIQUE INDEX uq_users_login_identifier
    ON users (normalized_login_identifier)
    WHERE normalized_login_identifier IS NOT NULL;

CREATE TABLE user_auth_methods (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    method_type         text NOT NULL CHECK (method_type IN ('passkey', 'oidc', 'password')),
    issuer              text NOT NULL,
    subject             text NOT NULL,
    credential_public_data jsonb,
    status              text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'disabled', 'revoked')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    last_used_at        timestamptz,
    UNIQUE (issuer, subject),
    UNIQUE (user_id, id)
);
CREATE INDEX ix_user_auth_methods_user ON user_auth_methods(user_id, status);

CREATE TABLE devices (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    public_key          bytea NOT NULL,
    public_key_sha256   bytea NOT NULL CHECK (octet_length(public_key_sha256) = 32),
    platform            text NOT NULL CHECK (platform IN ('android', 'windows', 'web', 'other')),
    app_version         text,
    device_label_envelope bytea,
    status              text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'revoked', 'retired')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    last_seen_at        timestamptz,
    revoked_at          timestamptz,
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    UNIQUE (user_id, id),
    UNIQUE (user_id, public_key_sha256),
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL))
);
CREATE INDEX ix_devices_user_status ON devices(user_id, status);

CREATE TABLE sessions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    device_id           uuid NOT NULL,
    token_hash          bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,
    last_used_at        timestamptz,
    revoked_at          timestamptz,
    FOREIGN KEY (user_id, device_id) REFERENCES devices(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, id),
    CHECK (expires_at > created_at)
);
CREATE INDEX ix_sessions_user_active ON sessions(user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE provider_accounts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    provider            text NOT NULL CHECK (provider IN ('google_drive', 'onedrive', 'dropbox', 's3_compatible', 'other')),
    provider_subject    text NOT NULL,
    display_label_envelope bytea,
    status              text NOT NULL DEFAULT 'connected'
                        CHECK (status IN ('pending', 'connected', 'reauth_required', 'disconnected', 'revoked', 'error')),
    granted_scopes      text[] NOT NULL DEFAULT '{}',
    capabilities        jsonb NOT NULL DEFAULT '{}'::jsonb,
    connected_at        timestamptz NOT NULL DEFAULT now(),
    last_checked_at     timestamptz,
    disconnected_at     timestamptz,
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    UNIQUE (user_id, id),
    UNIQUE (user_id, provider, provider_subject)
);
CREATE INDEX ix_provider_accounts_user_status ON provider_accounts(user_id, status);

-- Optional vault only. Keep empty/disabled until explicit product and threat-model approval.
CREATE TABLE provider_credentials (
    provider_account_id uuid PRIMARY KEY,
    user_id             uuid NOT NULL,
    encrypted_refresh_envelope bytea NOT NULL,
    envelope_version    integer NOT NULL CHECK (envelope_version > 0),
    kms_key_reference   text NOT NULL,
    kms_key_version     text NOT NULL,
    scopes              text[] NOT NULL DEFAULT '{}',
    token_expires_at    timestamptz,
    refresh_rotated_at  timestamptz,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT
);

CREATE TABLE file_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    metadata_envelope   bytea NOT NULL,
    metadata_format_version integer NOT NULL CHECK (metadata_format_version > 0),
    status              text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'tombstoned', 'conflict', 'quarantined')),
    current_version_id  uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    tombstoned_at       timestamptz,
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    UNIQUE (user_id, id),
    CHECK ((status = 'tombstoned') = (tombstoned_at IS NOT NULL))
);
CREATE INDEX ix_file_records_user_updated ON file_records(user_id, updated_at DESC, id);

CREATE TABLE file_versions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    file_id             uuid NOT NULL,
    version_number      bigint NOT NULL CHECK (version_number > 0),
    content_size_bytes  bigint NOT NULL CHECK (content_size_bytes >= 0),
    content_fingerprint_sha256 bytea NOT NULL CHECK (octet_length(content_fingerprint_sha256) = 32),
    encryption_format_version integer NOT NULL CHECK (encryption_format_version > 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, file_id) REFERENCES file_records(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, file_id, id),
    UNIQUE (user_id, file_id, version_number)
);
CREATE INDEX ix_file_versions_file_created ON file_versions(user_id, file_id, created_at DESC);

ALTER TABLE file_records
    ADD CONSTRAINT fk_file_records_current_version
    FOREIGN KEY (user_id, id, current_version_id)
    REFERENCES file_versions(user_id, file_id, id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE file_locations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    file_id             uuid NOT NULL,
    file_version_id     uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    provider_object_id  text NOT NULL,
    provider_parent_id  text,
    provider_version_tag text,
    remote_size_bytes   bigint CHECK (remote_size_bytes IS NULL OR remote_size_bytes >= 0),
    verified_at         timestamptz,
    verification_method text CHECK (verification_method IN ('provider_checksum', 'readback_hash', 'size_and_metadata', 'other')),
    verification_sha256 bytea CHECK (verification_sha256 IS NULL OR octet_length(verification_sha256) = 32),
    is_canonical        boolean NOT NULL DEFAULT false,
    status              text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('pending', 'active', 'missing', 'inaccessible', 'delete_pending', 'deleted')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, file_id, file_version_id)
        REFERENCES file_versions(user_id, file_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, provider_account_id)
        REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, provider_account_id, provider_object_id),
    CHECK (NOT is_canonical OR (verified_at IS NOT NULL AND status = 'active'))
);
CREATE UNIQUE INDEX uq_file_locations_one_canonical_per_version
    ON file_locations(user_id, file_version_id)
    WHERE is_canonical = true;
CREATE INDEX ix_file_locations_version ON file_locations(user_id, file_version_id);
CREATE INDEX ix_file_locations_account ON file_locations(user_id, provider_account_id, status);

CREATE TABLE sync_cursors (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL,
    device_id           uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    scope_key           text NOT NULL DEFAULT 'root',
    opaque_cursor_envelope bytea,
    last_success_at     timestamptz,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    row_version         bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    FOREIGN KEY (user_id, device_id) REFERENCES devices(user_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, provider_account_id) REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, device_id, provider_account_id, scope_key)
);

CREATE TABLE idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    operation_key       text NOT NULL,
    request_sha256      bytea NOT NULL CHECK (octet_length(request_sha256) = 32),
    response_status     integer,
    resource_type       text,
    resource_id         uuid,
    state               text NOT NULL DEFAULT 'in_progress'
                        CHECK (state IN ('in_progress', 'succeeded', 'failed_terminal')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,
    completed_at        timestamptz,
    UNIQUE (user_id, operation_key),
    CHECK (expires_at > created_at),
    CHECK ((state = 'in_progress' AND completed_at IS NULL) OR
           (state <> 'in_progress' AND completed_at IS NOT NULL))
);
CREATE INDEX ix_idempotency_expiry ON idempotency_records(expires_at);

CREATE TABLE audit_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid REFERENCES users(id) ON DELETE RESTRICT,
    actor_device_id     uuid,
    event_type          text NOT NULL,
    target_type         text,
    target_id           uuid,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    details_redacted    jsonb NOT NULL DEFAULT '{}'::jsonb,
    FOREIGN KEY (user_id, actor_device_id) REFERENCES devices(user_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_audit_events_user_time ON audit_events(user_id, occurred_at DESC);

CREATE TABLE outbox_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid REFERENCES users(id) ON DELETE RESTRICT,
    event_type          text NOT NULL,
    aggregate_type      text NOT NULL,
    aggregate_id        uuid NOT NULL,
    payload_reference   jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    available_at        timestamptz NOT NULL DEFAULT now(),
    processed_at        timestamptz,
    locked_until        timestamptz,
    attempt_count       integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error_code     text
);
CREATE INDEX ix_outbox_ready ON outbox_events(available_at, created_at)
    WHERE processed_at IS NULL;

COMMIT;

-- Application/migration-runner responsibilities not expressible here:
-- * Set updated_at and increment row_version atomically on mutable rows.
-- * Enforce session expiry/revocation and device revocation during auth.
-- * Enforce legal state transitions and verify provider evidence before canonical promotion.
-- * Restrict outbox payloads to non-secret references; never include OAuth tokens or raw session URLs.
-- * Implement user deletion as an audited staged workflow; do not CASCADE-delete user data.
