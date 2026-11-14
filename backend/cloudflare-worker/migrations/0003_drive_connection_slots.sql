CREATE TABLE IF NOT EXISTS drive_connection_slots (
  user_id TEXT NOT NULL,
  slot_id TEXT NOT NULL,
  label TEXT NOT NULL CHECK (length(label) BETWEEN 1 AND 48),
  sort_order INTEGER NOT NULL CHECK (sort_order BETWEEN 0 AND 19),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (user_id, slot_id),
  UNIQUE (user_id, sort_order)
);

CREATE INDEX IF NOT EXISTS drive_connection_slots_user_order_idx
  ON drive_connection_slots(user_id, sort_order);
