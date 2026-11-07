-- PostgreSQL smoke tests for V001. Runs inside a transaction and rolls back fixtures.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    u1 uuid;
    u2 uuid;
    d1 uuid;
    p1 uuid;
    p2 uuid;
    f1 uuid;
    v1 uuid;
    loc1 uuid;
BEGIN
    IF to_regclass('public.users') IS NULL
       OR to_regclass('public.file_records') IS NULL
       OR to_regclass('public.file_versions') IS NULL
       OR to_regclass('public.file_locations') IS NULL
       OR to_regclass('public.idempotency_records') IS NULL THEN
        RAISE EXCEPTION 'Required V001 tables are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'uq_file_locations_one_canonical_per_version'
    ) THEN
        RAISE EXCEPTION 'Canonical-location unique index is missing';
    END IF;

    INSERT INTO users(normalized_login_identifier)
    VALUES ('ci-user-one@example.invalid')
    RETURNING id INTO u1;

    INSERT INTO users(normalized_login_identifier)
    VALUES ('ci-user-two@example.invalid')
    RETURNING id INTO u2;

    INSERT INTO devices(user_id, public_key, public_key_sha256, platform)
    VALUES (u1, decode('01', 'hex'), decode(repeat('01', 32), 'hex'), 'android')
    RETURNING id INTO d1;

    INSERT INTO provider_accounts(user_id, provider, provider_subject)
    VALUES (u1, 'google_drive', 'ci-provider-subject-1')
    RETURNING id INTO p1;

    INSERT INTO provider_accounts(user_id, provider, provider_subject)
    VALUES (u2, 'google_drive', 'ci-provider-subject-2')
    RETURNING id INTO p2;

    INSERT INTO file_records(user_id, metadata_envelope, metadata_format_version)
    VALUES (u1, decode('01', 'hex'), 1)
    RETURNING id INTO f1;

    INSERT INTO file_versions(
        user_id, file_id, version_number, content_size_bytes,
        content_fingerprint_sha256, encryption_format_version
    )
    VALUES (u1, f1, 1, 1, decode(repeat('ab', 32), 'hex'), 1)
    RETURNING id INTO v1;

    UPDATE file_records
       SET current_version_id = v1
     WHERE user_id = u1 AND id = f1;

    INSERT INTO file_locations(
        user_id, file_id, file_version_id, provider_account_id,
        provider_object_id, verified_at, verification_method,
        verification_sha256, is_canonical
    )
    VALUES (
        u1, f1, v1, p1, 'ci-object-1', now(), 'readback_hash',
        decode(repeat('ab', 32), 'hex'), true
    )
    RETURNING id INTO loc1;

    -- A second canonical location for the same version must be rejected.
    BEGIN
        INSERT INTO file_locations(
            user_id, file_id, file_version_id, provider_account_id,
            provider_object_id, verified_at, verification_method,
            verification_sha256, is_canonical
        )
        VALUES (
            u1, f1, v1, p1, 'ci-object-2', now(), 'readback_hash',
            decode(repeat('ab', 32), 'hex'), true
        );
        RAISE EXCEPTION 'Duplicate canonical location unexpectedly succeeded';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    -- A file owned by user one must not point to user two's provider account.
    BEGIN
        INSERT INTO file_locations(
            user_id, file_id, file_version_id, provider_account_id,
            provider_object_id
        )
        VALUES (u1, f1, v1, p2, 'cross-user-object');
        RAISE EXCEPTION 'Cross-user provider-account link unexpectedly succeeded';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    -- Same idempotency key cannot be claimed twice for one user.
    INSERT INTO idempotency_records(
        user_id, operation_key, request_sha256, expires_at
    )
    VALUES (u1, 'ci-operation-1', decode(repeat('cd', 32), 'hex'), now() + interval '1 day');

    BEGIN
        INSERT INTO idempotency_records(
            user_id, operation_key, request_sha256, expires_at
        )
        VALUES (u1, 'ci-operation-1', decode(repeat('ef', 32), 'hex'), now() + interval '1 day');
        RAISE EXCEPTION 'Duplicate idempotency key unexpectedly succeeded';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;
