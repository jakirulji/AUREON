-- V003 PostgreSQL smoke tests; run after V001 and V002.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    u1 uuid; u2 uuid; d1 uuid; d2 uuid; p1 uuid; p2 uuid; trash1 uuid;
BEGIN
    IF to_regclass('public.trash_items') IS NULL THEN RAISE EXCEPTION 'V003 trash_items missing'; END IF;
    INSERT INTO users(normalized_login_identifier) VALUES ('v003-owner@example.invalid') RETURNING id INTO u1;
    INSERT INTO users(normalized_login_identifier) VALUES ('v003-other@example.invalid') RETURNING id INTO u2;
    INSERT INTO devices(user_id, public_key, public_key_sha256, platform)
      VALUES (u1, decode('31','hex'), decode(repeat('31',32),'hex'), 'android') RETURNING id INTO d1;
    INSERT INTO devices(user_id, public_key, public_key_sha256, platform)
      VALUES (u2, decode('32','hex'), decode(repeat('32',32),'hex'), 'windows') RETURNING id INTO d2;
    INSERT INTO provider_accounts(user_id, provider, provider_subject)
      VALUES (u1, 'google_drive', 'v003-owner-drive') RETURNING id INTO p1;
    INSERT INTO provider_accounts(user_id, provider, provider_subject)
      VALUES (u2, 'google_drive', 'v003-other-drive') RETURNING id INTO p2;
    INSERT INTO provider_items(user_id, provider_account_id, provider_item_id, item_kind, metadata_envelope, metadata_format_version)
      VALUES (u1, p1, 'cloud-item-1', 'file', decode('31','hex'), 1);
    INSERT INTO trash_items(user_id, provider_account_id, provider_item_id, original_parent_provider_item_id,
      trash_mode, operation_id, created_by_device_id, updated_by_device_id)
      VALUES (u1, p1, 'cloud-item-1', 'parent-1', 'provider_native',
      '00000000-0000-4000-8000-000000000031', d1, d1) RETURNING id INTO trash1;
    BEGIN
      INSERT INTO trash_items(user_id, provider_account_id, provider_item_id, trash_mode, operation_id, created_by_device_id, updated_by_device_id)
      VALUES (u1, p1, 'cloud-item-1', 'provider_native', '00000000-0000-4000-8000-000000000032', d1, d1);
      RAISE EXCEPTION 'Duplicate active Trash record unexpectedly succeeded';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO trash_items(user_id, provider_account_id, provider_item_id, trash_mode, operation_id, created_by_device_id, updated_by_device_id)
      VALUES (u1, p2, 'foreign-item', 'provider_native', '00000000-0000-4000-8000-000000000033', d1, d1);
      RAISE EXCEPTION 'Cross-user provider account reference unexpectedly succeeded';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    UPDATE trash_items SET status='restored', restored_at=now(), updated_by_device_id=d1,
      updated_at=now(), row_version=row_version+1 WHERE id=trash1 AND user_id=u1;
    IF (SELECT status FROM trash_items WHERE id=trash1) <> 'restored' THEN RAISE EXCEPTION 'Restore state not persisted'; END IF;
    INSERT INTO trash_items(user_id, provider_account_id, provider_item_id, trash_mode, operation_id, created_by_device_id, updated_by_device_id)
      VALUES (u1, p1, 'cloud-item-1', 'provider_folder', '00000000-0000-4000-8000-000000000034', d1, d1);
    IF (SELECT count(*) FROM information_schema.columns WHERE table_name='trash_items'
      AND column_name IN ('local_path','saf_uri','file_bytes')) <> 0 THEN
      RAISE EXCEPTION 'Local-only path/content column unexpectedly exists';
    END IF;
END $$;
ROLLBACK;
