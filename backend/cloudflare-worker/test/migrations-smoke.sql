.read migrations/0001_vault_recovery.sql
.read migrations/0002_recovery_challenge_rate_limit_index.sql
.read migrations/0003_drive_connection_slots.sql

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
SELECT 'Drive connection slot table', COUNT(*) = 1
FROM sqlite_master WHERE type = 'table' AND name = 'drive_connection_slots';

INSERT INTO migration_assertions
SELECT 'Drive connection slot owner/order index', COUNT(*) = 1
FROM sqlite_master WHERE type = 'index' AND name = 'drive_connection_slots_user_order_idx';

INSERT INTO migration_assertions
SELECT 'challenge rate-limit index', COUNT(*) = 1
FROM sqlite_master
WHERE type = 'index' AND name = 'recovery_challenges_user_vault_time_idx';

SELECT assertion FROM migration_assertions ORDER BY assertion;

-- Exercise the same conditional INSERT predicates used by the Worker route.
INSERT INTO recovery_challenges
  (challenge_id,user_id,vault_id,generation,challenge_sha256,expires_at_ms,created_at_ms)
VALUES
  ('cap-1','user-cap','vault-cap',1,'hash-1',1800000300000,1800000000000),
  ('cap-2','user-cap','vault-cap',1,'hash-2',1800000300000,1800000000000);

INSERT INTO recovery_challenges
  (challenge_id,user_id,vault_id,generation,challenge_sha256,expires_at_ms,created_at_ms)
SELECT 'cap-3','user-cap','vault-cap',1,'hash-3',1800000300000,1800000000000
WHERE (SELECT COUNT(*) FROM recovery_challenges
  WHERE user_id='user-cap' AND vault_id='vault-cap'
    AND created_at_ms>1799999400000) < 3
AND NOT EXISTS (SELECT 1 FROM recovery_cooldowns
  WHERE user_id='user-cap' AND vault_id='vault-cap'
    AND next_allowed_at_ms>1800000000000);

INSERT INTO migration_assertions
SELECT 'third recovery challenge is permitted', COUNT(*) = 3
FROM recovery_challenges WHERE user_id='user-cap' AND vault_id='vault-cap';

INSERT INTO recovery_challenges
  (challenge_id,user_id,vault_id,generation,challenge_sha256,expires_at_ms,created_at_ms)
SELECT 'cap-4','user-cap','vault-cap',1,'hash-4',1800000300000,1800000000000
WHERE (SELECT COUNT(*) FROM recovery_challenges
  WHERE user_id='user-cap' AND vault_id='vault-cap'
    AND created_at_ms>1799999400000) < 3
AND NOT EXISTS (SELECT 1 FROM recovery_cooldowns
  WHERE user_id='user-cap' AND vault_id='vault-cap'
    AND next_allowed_at_ms>1800000000000);

INSERT INTO migration_assertions
SELECT 'fourth recovery challenge is blocked', COUNT(*) = 3
FROM recovery_challenges WHERE user_id='user-cap' AND vault_id='vault-cap';

INSERT INTO recovery_cooldowns(user_id,vault_id,next_allowed_at_ms)
VALUES ('user-cooldown','vault-cooldown',1800001800000);

INSERT INTO recovery_challenges
  (challenge_id,user_id,vault_id,generation,challenge_sha256,expires_at_ms,created_at_ms)
SELECT 'cooldown-blocked','user-cooldown','vault-cooldown',1,'hash-5',1800000300000,1800000000000
WHERE (SELECT COUNT(*) FROM recovery_challenges
  WHERE user_id='user-cooldown' AND vault_id='vault-cooldown'
    AND created_at_ms>1799999400000) < 3
AND NOT EXISTS (SELECT 1 FROM recovery_cooldowns
  WHERE user_id='user-cooldown' AND vault_id='vault-cooldown'
    AND next_allowed_at_ms>1800000000000);

INSERT INTO migration_assertions
SELECT 'active recovery cooldown blocks challenge issuance', COUNT(*) = 0
FROM recovery_challenges WHERE user_id='user-cooldown' AND vault_id='vault-cooldown';
