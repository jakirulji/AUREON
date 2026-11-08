PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS vault_snapshots (
  user_id TEXT NOT NULL,
  vault_id TEXT NOT NULL,
  generation INTEGER NOT NULL CHECK (generation >= 1),
  created_at_ms INTEGER NOT NULL CHECK (created_at_ms > 0),
  snapshot_json TEXT NOT NULL,
  snapshot_sha256 TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (user_id, vault_id)
);

CREATE TABLE IF NOT EXISTS recovery_challenges (
  challenge_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  vault_id TEXT NOT NULL,
  generation INTEGER NOT NULL CHECK (generation >= 1),
  challenge_sha256 TEXT NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS recovery_challenges_expiry_idx ON recovery_challenges(expires_at_ms);

CREATE TABLE IF NOT EXISTS recovery_cooldowns (
  user_id TEXT NOT NULL,
  vault_id TEXT NOT NULL,
  next_allowed_at_ms INTEGER NOT NULL,
  PRIMARY KEY (user_id, vault_id)
);

CREATE TABLE IF NOT EXISTS security_audit_events (
  event_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  vault_id TEXT,
  event_type TEXT NOT NULL,
  generation INTEGER,
  created_at_ms INTEGER NOT NULL,
  details_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS security_audit_user_time_idx ON security_audit_events(user_id, created_at_ms DESC);
