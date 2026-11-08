.read migrations/0001_vault_recovery.sql
.read migrations/0002_recovery_challenge_rate_limit_index.sql

CREATE TEMP TABLE migration_assertions (
  assertion TEXT PRIMARY KEY,
  passed INTEGER NOT NULL CHECK (passed = 1)
);

INSERT INTO migration_assertions
SELECT 'vault_snapshots table', COUNT(*) = 1
FROM sqlite_master WHERE type = 'table' AND name = 'vault_snapshots';

INSERT INTO migration_assertions
SELECT 'recovery_challenges table', COUNT(*) = 1
FROM sqlite_master WHERE type = 'table' AND name = 'recovery_challenges';

INSERT INTO migration_assertions
SELECT 'recovery_cooldowns table', COUNT(*) = 1
FROM sqlite_master WHERE type = 'table' AND name = 'recovery_cooldowns';

INSERT INTO migration_assertions
SELECT 'security_audit_events table', COUNT(*) = 1
FROM sqlite_master WHERE type = 'table' AND name = 'security_audit_events';

INSERT INTO migration_assertions
SELECT 'challenge rate-limit index', COUNT(*) = 1
FROM sqlite_master
WHERE type = 'index' AND name = 'recovery_challenges_user_vault_time_idx';

SELECT assertion FROM migration_assertions ORDER BY assertion;
