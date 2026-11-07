-- PostgreSQL smoke tests for V002. Run after V001 and V002; transaction rolls back fixtures.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    u1 uuid;
    u2 uuid;
    d1 uuid;
    p1 uuid;
    p2 uuid;
    tx1 uuid;
    album1 uuid;
BEGIN
    IF to_regclass('public.provider_oauth_transactions') IS NULL
       OR to_regclass('public.provider_inventory_cursors') IS NULL
       OR to_regclass('public.provider_items') IS NULL
       OR to_regclass('public.provider_albums') IS NULL
       OR to_regclass('public.provider_album_memberships') IS NULL THEN
        RAISE EXCEPTION 'Required V002 tables are missing';
    END IF;

    INSERT INTO users(normalized_login_identifier)
    VALUES ('v002-user-one@example.invalid') RETURNING id INTO u1;
    INSERT INTO users(normalized_login_identifier)
    VALUES ('v002-user-two@example.invalid') RETURNING id INTO u2;

    INSERT INTO devices(user_id, public_key, public_key_sha256, platform)
    VALUES (u1, decode('02', 'hex'), decode(repeat('02', 32), 'hex'), 'android')
    RETURNING id INTO d1;

    INSERT INTO provider_accounts(user_id, provider, provider_subject)
    VALUES (u1, 'google_drive', 'v002-drive-subject')
    RETURNING id INTO p1;
    INSERT INTO provider_accounts(user_id, provider, provider_subject)
    VALUES (u2, 'google_drive', 'v002-other-subject')
    RETURNING id INTO p2;

    -- Envelope is opaque test ciphertext; production bytes must be KMS-wrapped AEAD.
    INSERT INTO provider_credentials(
        provider_account_id, user_id, encrypted_refresh_envelope,
        envelope_version, kms_key_reference, kms_key_version,
        encryption_algorithm, credential_version, credential_status, consented_at
    ) VALUES (
        p1, u1, decode('aabbcc', 'hex'), 1, 'ci/kms/aureon-test', 'key-v1',
        'AES-256-GCM', 1, 'active', now()
    );

    INSERT INTO provider_oauth_transactions(
        user_id, device_id, provider, state_sha256, pkce_challenge_sha256,
        callback_mode, redirect_uri, requested_scopes, expires_at
    ) VALUES (
        u1, d1, 'google_drive', decode(repeat('11', 32), 'hex'),
        decode(repeat('22', 32), 'hex'), 'native_app',
        'com.example.aureon:/oauth2redirect', ARRAY['drive.readonly'], now() + interval '5 minutes'
    ) RETURNING id INTO tx1;

    -- State hash must be globally unique to prevent transaction ambiguity/replay.
    BEGIN
        INSERT INTO provider_oauth_transactions(
            user_id, device_id, provider, state_sha256, pkce_challenge_sha256,
            callback_mode, redirect_uri, expires_at
        ) VALUES (
            u1, d1, 'google_drive', decode(repeat('11', 32), 'hex'),
            decode(repeat('33', 32), 'hex'), 'native_app',
            'com.example.aureon:/oauth2redirect', now() + interval '5 minutes'
        );
        RAISE EXCEPTION 'Duplicate OAuth state hash unexpectedly succeeded';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO provider_inventory_cursors(user_id, provider_account_id, scope_key, initial_scan_state)
    VALUES (u1, p1, 'drive-root', 'running');

    INSERT INTO provider_items(
        user_id, provider_account_id, provider_item_id, item_kind,
        mime_type, metadata_envelope, metadata_format_version
    ) VALUES (
        u1, p1, 'root-folder', 'folder', 'application/vnd.google-apps.folder',
        decode('01', 'hex'), 1
    );

    INSERT INTO provider_items(
        user_id, provider_account_id, provider_item_id, parent_provider_item_id,
        item_kind, mime_type, metadata_envelope, metadata_format_version
    ) VALUES (
        u1, p1, 'nested-document', 'root-folder', 'file', 'application/pdf',
        decode('02', 'hex'), 1
    );

    -- Cross-user provider inventory references must fail.
    BEGIN
        INSERT INTO provider_items(
            user_id, provider_account_id, provider_item_id, item_kind,
            metadata_envelope, metadata_format_version
        ) VALUES (u1, p2, 'cross-user-item', 'file', decode('03', 'hex'), 1);
        RAISE EXCEPTION 'Cross-user inventory reference unexpectedly succeeded';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO provider_accounts(user_id, provider, provider_subject)
    VALUES (u1, 'google_photos', 'v002-photos-subject');

    INSERT INTO provider_albums(
        user_id, provider_account_id, provider_album_id, metadata_envelope, metadata_format_version
    ) VALUES (u1, p1, 'album-1', decode('04', 'hex'), 1)
    RETURNING id INTO album1;

    INSERT INTO provider_album_memberships(
        user_id, provider_account_id, album_id, provider_media_item_id
    ) VALUES (u1, p1, album1, 'media-1');

    -- A completed transaction must have a consumed timestamp and account binding.
    BEGIN
        UPDATE provider_oauth_transactions
           SET status = 'completed', consumed_at = now()
         WHERE id = tx1;
        RAISE EXCEPTION 'Completed OAuth transaction without account binding unexpectedly succeeded';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    -- Refreshing credentials require an active lease.
    BEGIN
        UPDATE provider_credentials
           SET credential_status = 'refreshing',
               refresh_lease_id = NULL,
               refresh_lease_expires_at = NULL
         WHERE provider_account_id = p1;
        RAISE EXCEPTION 'Refresh without lease unexpectedly succeeded';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;
