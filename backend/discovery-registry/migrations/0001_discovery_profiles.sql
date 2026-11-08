CREATE TABLE IF NOT EXISTS discovery_profiles (
  discovery_id_hash TEXT PRIMARY KEY NOT NULL,
  firebase_project_id TEXT NOT NULL,
  firebase_api_key TEXT NOT NULL,
  firebase_auth_domain TEXT NOT NULL,
  firebase_app_id TEXT NOT NULL,
  worker_base_url TEXT NOT NULL,
  firebase_issuer TEXT NOT NULL,
  firebase_uid TEXT NOT NULL,
  profile_version INTEGER NOT NULL CHECK (profile_version >= 1),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_discovery_profiles_owner
  ON discovery_profiles(firebase_issuer, firebase_uid);
