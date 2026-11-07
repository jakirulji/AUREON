-- V003: provider-backed Trash metadata for cross-device reconciliation.
-- Local SAF/Win32 paths, content:// URIs and file bytes are intentionally excluded.
BEGIN;
CREATE TABLE trash_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    provider_item_id text NOT NULL CHECK (length(provider_item_id) BETWEEN 1 AND 1024),
    original_parent_provider_item_id text CHECK (original_parent_provider_item_id IS NULL OR length(original_parent_provider_item_id) <= 1024),
    trash_mode text NOT NULL CHECK (trash_mode IN ('provider_native', 'provider_folder')),
    trash_container_provider_item_id text CHECK (trash_container_provider_item_id IS NULL OR length(trash_container_provider_item_id) <= 1024),
    status text NOT NULL DEFAULT 'trashed' CHECK (status IN ('trashed', 'restored', 'permanently_deleted')),
    operation_id uuid NOT NULL,
    created_by_device_id uuid NOT NULL,
    updated_by_device_id uuid NOT NULL,
    trashed_at timestamptz NOT NULL DEFAULT now(),
    restored_at timestamptz,
    permanently_deleted_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
    FOREIGN KEY (user_id, provider_account_id) REFERENCES provider_accounts(user_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, provider_account_id, provider_item_id)
        REFERENCES provider_items(user_id, provider_account_id, provider_item_id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, created_by_device_id) REFERENCES devices(user_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, updated_by_device_id) REFERENCES devices(user_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, id),
    UNIQUE (user_id, operation_id),
    CHECK (
        (status = 'trashed' AND restored_at IS NULL AND permanently_deleted_at IS NULL)
        OR (status = 'restored' AND restored_at IS NOT NULL AND permanently_deleted_at IS NULL)
        OR (status = 'permanently_deleted' AND restored_at IS NULL AND permanently_deleted_at IS NOT NULL)
    ),
    CHECK (
        (trash_mode = 'provider_native' AND trash_container_provider_item_id IS NULL)
        OR (trash_mode = 'provider_folder' AND trash_container_provider_item_id IS NOT NULL)
    )
);
CREATE UNIQUE INDEX uq_trash_items_one_active_provider_object
    ON trash_items(user_id, provider_account_id, provider_item_id) WHERE status = 'trashed';
CREATE INDEX ix_trash_items_user_recent ON trash_items(user_id, trashed_at DESC, id DESC);
CREATE INDEX ix_trash_items_account_status ON trash_items(user_id, provider_account_id, status, trashed_at DESC);
COMMENT ON TABLE trash_items IS 'Cross-device metadata for provider-backed Trash only; no local paths, SAF URIs or file bytes.';
COMMIT;
