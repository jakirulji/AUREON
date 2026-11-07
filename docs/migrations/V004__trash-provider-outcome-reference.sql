-- V004: persist provider-side outcome references for Trash lifecycle audit.
-- Existing rows remain NULL; no unverifiable receipt is fabricated.
BEGIN;
ALTER TABLE trash_items
    ADD COLUMN provider_outcome_reference text
        CHECK (provider_outcome_reference IS NULL OR length(provider_outcome_reference) BETWEEN 1 AND 2048);
COMMENT ON COLUMN trash_items.provider_outcome_reference IS
    'Non-secret provider response reference/ETag proving the provider adapter completed the last lifecycle action; never an OAuth token or file content.';
COMMIT;
