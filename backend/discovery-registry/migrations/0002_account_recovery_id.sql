-- Preserve every existing opaque locator and owner binding while giving it its canonical Account Recovery ID name.
ALTER TABLE discovery_profiles RENAME COLUMN discovery_id_hash TO account_recovery_id_hash;
