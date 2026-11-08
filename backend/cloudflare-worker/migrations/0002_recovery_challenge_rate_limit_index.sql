CREATE INDEX IF NOT EXISTS recovery_challenges_user_vault_time_idx
  ON recovery_challenges(user_id, vault_id, created_at_ms);
