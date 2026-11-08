import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

interface Env {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  AUREON_VAULT_ROOT_SECRET_V1?: string;
  AUREON_VAULT_ROOT_SECRET_V2?: string;
  AUREON_VAULT_ACTIVE_ROOT_VERSION: string;
}
interface FirebaseIdentity { uid: string; email: string; authTime: number }
interface VaultSnapshot {
  format: "AUREON-VAULT-RECOVERY-BUNDLE";
  formatVersion: 1;
  vaultId: string;
  generation: number;
  createdAtEpochMs: number;
  encryptedCredentialRecords: Array<Record<string, unknown>>;
  manualKeyEnvelopes: Array<Record<string, unknown>>;
  cloudflareEnvelope: Record<string, unknown>;
}

const FIREBASE_JWKS = createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"));
const MAX_BODY_BYTES = 1024 * 1024;
const MAX_RECORDS = 256;
const CHALLENGE_TTL_MS = 5 * 60 * 1000;
const RECOVERY_COOLDOWN_MS = 30 * 60 * 1000;
const RECENT_AUTH_SECONDS = 5 * 60;

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: {
    "content-type": "application/json; charset=utf-8", "cache-control": "no-store",
    "x-content-type-options": "nosniff", "referrer-policy": "no-referrer",
  }});
}
function base64Url(bytes: Uint8Array): string {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function fromBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new HttpError(400, "Invalid base64url value.");
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}
function randomBytes(length: number): Uint8Array { return crypto.getRandomValues(new Uint8Array(length)); }
async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
async function authenticate(request: Request, env: Env, requireRecentAuth = false): Promise<FirebaseIdentity> {
  const match = /^Bearer ([^\s]+)$/.exec(request.headers.get("authorization") ?? "");
  if (!match) throw new HttpError(401, "A Firebase ID token is required.");
  let payload: JWTPayload;
  try {
    payload = (await jwtVerify(match[1]!, FIREBASE_JWKS, {
      algorithms: ["RS256"], issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
    })).payload;
  } catch { throw new HttpError(401, "Firebase ID token is invalid or expired."); }
  const uid = payload.sub;
  const email = typeof payload.email === "string" ? payload.email : "";
  const authTime = typeof payload.auth_time === "number" ? payload.auth_time : 0;
  if (!uid || !email || payload.email_verified !== true || !authTime) {
    throw new HttpError(403, "A verified Firebase email account is required.");
  }
  if (requireRecentAuth && Math.floor(Date.now() / 1000) - authTime > RECENT_AUTH_SECONDS) {
    throw new HttpError(401, "Recent reauthentication is required.");
  }
  return { uid, email, authTime };
}
async function readJson(request: Request): Promise<Record<string, unknown>> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY_BYTES) throw new HttpError(413, "Request body is too large.");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) throw new HttpError(413, "Request body is too large.");
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return parsed as Record<string, unknown>;
  } catch { throw new HttpError(400, "A valid JSON object is required."); }
}
function requiredString(value: unknown, field: string, max = 256): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) throw new HttpError(400, `Invalid ${field}.`);
  return value;
}
function positiveInteger(value: unknown, field: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) throw new HttpError(400, `Invalid ${field}.`);
  return value as number;
}
function rejectPlaintextSecrets(value: unknown, path = "root"): void {
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (/^(accessToken|refreshToken|idToken|providerPassword|manualRecoveryKey|recoveryKey|plaintextDek|dek)$/i.test(key)) {
      throw new HttpError(400, `Plaintext secret field is forbidden at ${path}.`);
    }
    rejectPlaintextSecrets(child, `${path}.${key}`);
  }
}
export function validateSnapshot(input: Record<string, unknown>): VaultSnapshot {
  if (input.format !== "AUREON-VAULT-RECOVERY-BUNDLE" || input.formatVersion !== 1) throw new HttpError(400, "Unsupported vault bundle format.");
  const vaultId = requiredString(input.vaultId, "vaultId");
  const generation = positiveInteger(input.generation, "generation");
  const createdAtEpochMs = positiveInteger(input.createdAtEpochMs, "createdAtEpochMs");
  if (!Array.isArray(input.encryptedCredentialRecords) || input.encryptedCredentialRecords.length > MAX_RECORDS) throw new HttpError(400, "Credential record count is invalid.");
  if (!Array.isArray(input.manualKeyEnvelopes) || input.manualKeyEnvelopes.length !== 5) throw new HttpError(400, "Exactly five manual recovery envelopes are required.");
  if (!input.cloudflareEnvelope || typeof input.cloudflareEnvelope !== "object" || Array.isArray(input.cloudflareEnvelope)) throw new HttpError(400, "A Cloudflare recovery envelope is required.");
  const ids = new Set<string>();
  for (const record of input.encryptedCredentialRecords) {
    if (!record || typeof record !== "object" || Array.isArray(record)) throw new HttpError(400, "Invalid credential record.");
    const item = record as Record<string, unknown>; rejectPlaintextSecrets(item);
    const id = requiredString(item.providerAccountId, "providerAccountId");
    if (ids.has(id)) throw new HttpError(400, "Duplicate provider account record."); ids.add(id);
    if (item.formatVersion !== 1 || item.recordVersion !== 1 || item.cipher !== "AES-256-GCM") throw new HttpError(400, "Unsupported credential record format.");
    const nonce = fromBase64Url(requiredString(item.nonce, "record nonce", 64));
    const ciphertext = fromBase64Url(requiredString(item.cipherText, "record ciphertext", 1_400_000));
    const mac = fromBase64Url(requiredString(item.mac, "record MAC", 64));
    if (nonce.length !== 12 || ciphertext.length < 1 || ciphertext.length > 1024 * 1024 || mac.length !== 16) throw new HttpError(400, "Credential record cryptographic fields are invalid.");
  }
  const keyIds = new Set<string>();
  for (const envelope of input.manualKeyEnvelopes) {
    if (!envelope || typeof envelope !== "object" || Array.isArray(envelope)) throw new HttpError(400, "Invalid manual envelope.");
    const item = envelope as Record<string, unknown>; rejectPlaintextSecrets(item);
    const keyId = requiredString(item.keyId, "manual envelope keyId");
    if (keyIds.has(keyId)) throw new HttpError(400, "Duplicate manual key ID."); keyIds.add(keyId);
    if (fromBase64Url(requiredString(item.nonce, "manual nonce")).length !== 12 ||
        fromBase64Url(requiredString(item.salt, "manual salt")).length !== 32 ||
        fromBase64Url(requiredString(item.cipherText, "manual ciphertext")).length !== 32 ||
        fromBase64Url(requiredString(item.mac, "manual MAC")).length !== 16) throw new HttpError(400, "Manual envelope cryptographic fields are invalid.");
  }
  rejectPlaintextSecrets(input.cloudflareEnvelope);
  const cloudflare = input.cloudflareEnvelope as Record<string, unknown>;
  const rootKeyVersion = positiveInteger(cloudflare.rootKeyVersion, "Cloudflare rootKeyVersion");
  if (rootKeyVersion > 2 || cloudflare.formatVersion !== 1 || cloudflare.algorithm !== "HKDF-SHA-256/AES-256-GCM" ||
      fromBase64Url(requiredString(cloudflare.salt, "Cloudflare salt")).length !== 32 ||
      fromBase64Url(requiredString(cloudflare.nonce, "Cloudflare nonce")).length !== 12 ||
      fromBase64Url(requiredString(cloudflare.cipherText, "Cloudflare ciphertext")).length !== 48) {
    throw new HttpError(400, "Cloudflare envelope cryptographic fields are invalid.");
  }
  return { format: "AUREON-VAULT-RECOVERY-BUNDLE", formatVersion: 1, vaultId, generation, createdAtEpochMs,
    encryptedCredentialRecords: input.encryptedCredentialRecords as Array<Record<string, unknown>>,
    manualKeyEnvelopes: input.manualKeyEnvelopes as Array<Record<string, unknown>>,
    cloudflareEnvelope: input.cloudflareEnvelope as Record<string, unknown> };
}
function activeRootVersion(env: Env): number {
  const version = Number(env.AUREON_VAULT_ACTIVE_ROOT_VERSION);
  if (!Number.isSafeInteger(version) || version < 1 || version > 2) throw new HttpError(503, "Vault recovery root-key version is not configured.");
  return version;
}
async function deriveRootKey(env: Env, keyVersion: number, salt: Uint8Array, vaultId: string, generation: number): Promise<CryptoKey> {
  if (keyVersion < 1 || keyVersion > 2) throw new HttpError(409, "Unsupported Cloudflare root-key version.");
  const secret = keyVersion === 1 ? env.AUREON_VAULT_ROOT_SECRET_V1 : env.AUREON_VAULT_ROOT_SECRET_V2;
  if (!secret) throw new HttpError(503, "Required historical vault recovery root key is unavailable.");
  const root = fromBase64Url(secret);
  if (root.length !== 32) throw new HttpError(503, "Vault recovery service is not configured.");
  const material = await crypto.subtle.importKey("raw", root, "HKDF", false, ["deriveKey"]);
  root.fill(0);
  return crypto.subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt,
    info: new TextEncoder().encode(`AUREON|CREDENTIAL-VAULT|CLOUDFLARE-WRAP|v1|${vaultId}|${generation}`) },
    material, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
async function createCloudflareEnvelope(dek: Uint8Array, vaultId: string, generation: number, env: Env) {
  if (dek.length !== 32) throw new HttpError(400, "Vault DEK must be exactly 32 bytes.");
  const rootKeyVersion = activeRootVersion(env);
  const salt = randomBytes(32), nonce = randomBytes(12), key = await deriveRootKey(env, rootKeyVersion, salt, vaultId, generation);
  const aad = new TextEncoder().encode(`AUREON|CLOUDFLARE-ENVELOPE|v1|${vaultId}|${generation}`);
  const encrypted = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad, tagLength: 128 }, key, dek));
  return { formatVersion: 1, rootKeyVersion, algorithm: "HKDF-SHA-256/AES-256-GCM", salt: base64Url(salt), nonce: base64Url(nonce), cipherText: base64Url(encrypted) };
}
async function unwrapAndRewrap(envelope: Record<string, unknown>, vaultId: string, generation: number, deviceJwk: JsonWebKey, env: Env) {
  if (envelope.formatVersion !== 1 || envelope.algorithm !== "HKDF-SHA-256/AES-256-GCM") throw new HttpError(409, "Unsupported Cloudflare envelope version.");
  const rootKeyVersion = positiveInteger(envelope.rootKeyVersion, "Cloudflare rootKeyVersion");
  const salt = fromBase64Url(requiredString(envelope.salt, "Cloudflare salt"));
  const nonce = fromBase64Url(requiredString(envelope.nonce, "Cloudflare nonce"));
  const ciphertext = fromBase64Url(requiredString(envelope.cipherText, "Cloudflare ciphertext", 128));
  if (salt.length !== 32 || nonce.length !== 12 || ciphertext.length !== 48) throw new HttpError(409, "Cloudflare envelope is malformed.");
  const rootKey = await deriveRootKey(env, rootKeyVersion, salt, vaultId, generation);
  const aad = new TextEncoder().encode(`AUREON|CLOUDFLARE-ENVELOPE|v1|${vaultId}|${generation}`);
  let dek: Uint8Array;
  try { dek = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: aad, tagLength: 128 }, rootKey, ciphertext)); }
  catch { throw new HttpError(409, "Cloudflare envelope authentication failed."); }
  try {
    if (dek.length !== 32) throw new HttpError(409, "Recovered vault key has an invalid length.");
    if (deviceJwk.kty !== "EC" || deviceJwk.crv !== "P-256" || typeof deviceJwk.x !== "string" || typeof deviceJwk.y !== "string") throw new HttpError(400, "A P-256 device public key is required.");
    const devicePublic = await crypto.subtle.importKey("jwk", deviceJwk, { name: "ECDH", namedCurve: "P-256" }, false, []);
    const ephemeral = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
    const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: devicePublic }, ephemeral.privateKey, 256));
    const wrapSalt = randomBytes(32), wrapNonce = randomBytes(12);
    const material = await crypto.subtle.importKey("raw", shared, "HKDF", false, ["deriveKey"]); shared.fill(0);
    const info = new TextEncoder().encode(`AUREON|DEVICE-BOUND-VAULT-DEK|v1|${vaultId}|${generation}`);
    const wrapKey = await crypto.subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt: wrapSalt, info }, material, { name: "AES-GCM", length: 256 }, false, ["encrypt"]);
    const wrapped = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: wrapNonce, additionalData: info, tagLength: 128 }, wrapKey, dek));
    return { formatVersion: 1, algorithm: "ECDH-P256/HKDF-SHA-256/AES-256-GCM", vaultId, generation,
      serverEphemeralPublicKey: await crypto.subtle.exportKey("jwk", ephemeral.publicKey),
      salt: base64Url(wrapSalt), nonce: base64Url(wrapNonce), cipherText: base64Url(wrapped) };
  } finally { dek.fill(0); }
}
function auditStatement(env: Env, userId: string, vaultId: string | null, eventType: string, generation: number | null, details: Record<string, unknown> = {}) {
  return env.DB.prepare("INSERT INTO security_audit_events (event_id,user_id,vault_id,event_type,generation,created_at_ms,details_json) VALUES (?,?,?,?,?,?,?)")
    .bind(base64Url(randomBytes(18)), userId, vaultId, eventType, generation, Date.now(), JSON.stringify(details));
}
async function audit(env: Env, userId: string, vaultId: string | null, eventType: string, generation: number | null, details: Record<string, unknown> = {}) {
  const result = await auditStatement(env, userId, vaultId, eventType, generation, details).run();
  if (!result.success) throw new HttpError(503, "Security audit persistence failed; operation aborted.");
}
async function uploadSnapshot(request: Request, env: Env, identity: FirebaseIdentity): Promise<Response> {
  const snapshot = validateSnapshot(await readJson(request)), canonical = JSON.stringify(snapshot), hash = await sha256Hex(canonical);
  const existing = await env.DB.prepare("SELECT generation FROM vault_snapshots WHERE user_id=? AND vault_id=?")
    .bind(identity.uid, snapshot.vaultId).first<{ generation: number }>();
  if (!existing && snapshot.generation !== 1) throw new HttpError(409, "Initial vault generation must be 1.");
  if (existing && snapshot.generation !== existing.generation + 1) throw new HttpError(409, "Vault generation must advance exactly once.");
  const now = Date.now();
  const results = await env.DB.batch([
    env.DB.prepare(`INSERT INTO vault_snapshots (user_id,vault_id,generation,created_at_ms,snapshot_json,snapshot_sha256,updated_at_ms)
      VALUES (?,?,?,?,?,?,?) ON CONFLICT(user_id,vault_id) DO UPDATE SET generation=excluded.generation,
      created_at_ms=excluded.created_at_ms,snapshot_json=excluded.snapshot_json,snapshot_sha256=excluded.snapshot_sha256,updated_at_ms=excluded.updated_at_ms
      WHERE vault_snapshots.generation=excluded.generation-1`)
      .bind(identity.uid, snapshot.vaultId, snapshot.generation, snapshot.createdAtEpochMs, canonical, hash, now),
    env.DB.prepare("INSERT INTO security_audit_events (event_id,user_id,vault_id,event_type,generation,created_at_ms,details_json) SELECT ?,?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM vault_snapshots WHERE user_id=? AND vault_id=? AND generation=?)")
      .bind(base64Url(randomBytes(18)), identity.uid, snapshot.vaultId, "vault.snapshot.updated", snapshot.generation, now,
        JSON.stringify({ recordCount: snapshot.encryptedCredentialRecords.length }), identity.uid, snapshot.vaultId, snapshot.generation),
  ]);
  const [snapshotWrite, auditWrite] = results;
  if (!snapshotWrite || !auditWrite || !snapshotWrite.success || snapshotWrite.meta.changes !== 1 ||
      !auditWrite.success || auditWrite.meta.changes !== 1) throw new HttpError(409, "Vault update or audit failed; transaction was rolled back.");
  return json({ vaultId: snapshot.vaultId, generation: snapshot.generation, snapshotSha256: hash, storedAtEpochMs: now });
}
async function getSnapshot(request: Request, env: Env, identity: FirebaseIdentity): Promise<Response> {
  const vaultId = requiredString(new URL(request.url).searchParams.get("vaultId"), "vaultId");
  const row = await env.DB.prepare("SELECT generation,created_at_ms,snapshot_json,snapshot_sha256,updated_at_ms FROM vault_snapshots WHERE user_id=? AND vault_id=?")
    .bind(identity.uid, vaultId).first<{ generation: number; created_at_ms: number; snapshot_json: string; snapshot_sha256: string; updated_at_ms: number }>();
  if (!row) throw new HttpError(404, "Vault not found.");
  return json({ snapshot: JSON.parse(row.snapshot_json), snapshotSha256: row.snapshot_sha256,
    generation: row.generation, createdAtEpochMs: row.created_at_ms, updatedAtEpochMs: row.updated_at_ms });
}
async function issueChallenge(request: Request, env: Env, identity: FirebaseIdentity): Promise<Response> {
  const vaultId = requiredString((await readJson(request)).vaultId, "vaultId");
  const row = await env.DB.prepare("SELECT generation FROM vault_snapshots WHERE user_id=? AND vault_id=?")
    .bind(identity.uid, vaultId).first<{ generation: number }>();
  if (!row) throw new HttpError(404, "Vault not found.");
  const now = Date.now();
  const cooldown = await env.DB.prepare("SELECT next_allowed_at_ms FROM recovery_cooldowns WHERE user_id=? AND vault_id=?")
    .bind(identity.uid, vaultId).first<{ next_allowed_at_ms: number }>();
  if (cooldown && cooldown.next_allowed_at_ms > now) throw new HttpError(429, "Recovery cooldown is active.");
  const recent = await env.DB.prepare("SELECT COUNT(*) AS count FROM recovery_challenges WHERE user_id=? AND vault_id=? AND created_at_ms>?")
    .bind(identity.uid, vaultId, now - 10 * 60 * 1000).first<{ count: number }>();
  if ((recent?.count ?? 0) >= 3) throw new HttpError(429, "Too many recovery challenges; try again later.");
  const challengeId = base64Url(randomBytes(18)), challenge = base64Url(randomBytes(32)), hash = await sha256Hex(challenge);
  const results = await env.DB.batch([
    env.DB.prepare("INSERT INTO recovery_challenges (challenge_id,user_id,vault_id,generation,challenge_sha256,expires_at_ms,created_at_ms) VALUES (?,?,?,?,?,?,?)")
      .bind(challengeId, identity.uid, vaultId, row.generation, hash, now + CHALLENGE_TTL_MS, now),
    env.DB.prepare("INSERT INTO security_audit_events (event_id,user_id,vault_id,event_type,generation,created_at_ms,details_json) SELECT ?,?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM recovery_challenges WHERE challenge_id=? AND user_id=? AND vault_id=?)")
      .bind(base64Url(randomBytes(18)), identity.uid, vaultId, "vault.recovery.challenge_issued", row.generation, now, "{}",
        challengeId, identity.uid, vaultId),
  ]);
  const [challengeWrite, auditWrite] = results;
  if (!challengeWrite || !auditWrite || !challengeWrite.success || challengeWrite.meta.changes !== 1 ||
      !auditWrite.success || auditWrite.meta.changes !== 1) throw new HttpError(503, "Challenge/audit transaction failed.");
  return json({ challengeId, challenge, generation: row.generation, expiresAtEpochMs: now + CHALLENGE_TTL_MS });
}

async function recoverVault(request: Request, env: Env, identity: FirebaseIdentity): Promise<Response> {
  const body = await readJson(request), vaultId = requiredString(body.vaultId, "vaultId");
  const challengeId = requiredString(body.challengeId, "challengeId"), challenge = requiredString(body.challenge, "challenge", 128);
  if (!body.devicePublicKey || typeof body.devicePublicKey !== "object" || Array.isArray(body.devicePublicKey)) throw new HttpError(400, "A device-generated ephemeral public key is required.");
  const row = await env.DB.prepare("SELECT generation,snapshot_json FROM vault_snapshots WHERE user_id=? AND vault_id=?")
    .bind(identity.uid, vaultId).first<{ generation: number; snapshot_json: string }>();
  if (!row) throw new HttpError(404, "Vault not found.");
  const challengeRow = await env.DB.prepare("SELECT generation,challenge_sha256,expires_at_ms FROM recovery_challenges WHERE challenge_id=? AND user_id=? AND vault_id=?")
    .bind(challengeId, identity.uid, vaultId).first<{ generation: number; challenge_sha256: string; expires_at_ms: number }>();
  if (!challengeRow || challengeRow.expires_at_ms < Date.now() || challengeRow.generation !== row.generation ||
      challengeRow.challenge_sha256 !== await sha256Hex(challenge)) throw new HttpError(401, "Recovery challenge is invalid, expired, or already consumed.");
  const snapshot = JSON.parse(row.snapshot_json) as VaultSnapshot;
  const deviceBoundEnvelope = await unwrapAndRewrap(snapshot.cloudflareEnvelope, vaultId, row.generation, body.devicePublicKey as JsonWebKey, env);
  const now = Date.now();
  const results = await env.DB.batch([
    env.DB.prepare("INSERT INTO security_audit_events (event_id,user_id,vault_id,event_type,generation,created_at_ms,details_json) SELECT ?,?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM recovery_challenges WHERE challenge_id=? AND user_id=? AND vault_id=? AND challenge_sha256=? AND expires_at_ms>=?)")
      .bind(base64Url(randomBytes(18)), identity.uid, vaultId, "vault.recovery.completed", row.generation, now,
        JSON.stringify({ method: "cloudflare-device-bound" }), challengeId, identity.uid, vaultId, challengeRow.challenge_sha256, now),
    env.DB.prepare("DELETE FROM recovery_challenges WHERE challenge_id=? AND challenge_sha256=? AND expires_at_ms>=?")
      .bind(challengeId, challengeRow.challenge_sha256, now),
    env.DB.prepare("INSERT INTO recovery_cooldowns (user_id,vault_id,next_allowed_at_ms) VALUES (?,?,?) ON CONFLICT(user_id,vault_id) DO UPDATE SET next_allowed_at_ms=excluded.next_allowed_at_ms")
      .bind(identity.uid, vaultId, now + RECOVERY_COOLDOWN_MS),
  ]);
  const [auditWrite, challengeDelete, cooldownWrite] = results;
  if (!auditWrite || !challengeDelete || !cooldownWrite || !auditWrite.success || auditWrite.meta.changes !== 1 ||
      !challengeDelete.success || challengeDelete.meta.changes !== 1 || !cooldownWrite.success) {
    throw new HttpError(409, "Recovery completion/audit transaction failed.");
  }
  return json({ vaultId, generation: row.generation, deviceBoundEnvelope });
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204 });
    try {
      if (url.pathname === "/health/live" && request.method === "GET") return json({ status: "ok" });
      if (url.pathname === "/health/ready" && request.method === "GET") {
        const configured = env.FIREBASE_PROJECT_ID !== "REPLACE_WITH_FIREBASE_PROJECT_ID" && Boolean(env.AUREON_VAULT_ACTIVE_ROOT_VERSION) && Boolean(env.AUREON_VAULT_ROOT_SECRET_V1 || env.AUREON_VAULT_ROOT_SECRET_V2);
        const db = await env.DB.prepare("SELECT 1 AS ok").first<{ ok: number }>();
        return json({ ready: configured && db?.ok === 1 }, configured && db?.ok === 1 ? 200 : 503);
      }
      const sensitive = url.pathname === "/v1/vault/envelope" || url.pathname === "/v1/vault/recovery/challenge" || url.pathname === "/v1/vault/recovery/rewrap";
      const identity = await authenticate(request, env, sensitive);
      if (url.pathname === "/v1/vault/envelope" && request.method === "POST") {
        const body = await readJson(request), vaultId = requiredString(body.vaultId, "vaultId");
        const generation = positiveInteger(body.generation, "generation"), dek = fromBase64Url(requiredString(body.dek, "dek", 128));
        try {
          const envelope = await createCloudflareEnvelope(dek, vaultId, generation, env);
          await audit(env, identity.uid, vaultId, "vault.cloudflare_envelope.created", generation);
          return json({ envelope });
        } finally { dek.fill(0); }
      }
      if (url.pathname === "/v1/vault/snapshot" && request.method === "GET") return await getSnapshot(request, env, identity);
      if (url.pathname === "/v1/vault/snapshot" && request.method === "PUT") return await uploadSnapshot(request, env, identity);
      if (url.pathname === "/v1/vault/recovery/challenge" && request.method === "POST") return await issueChallenge(request, env, identity);
      if (url.pathname === "/v1/vault/recovery/rewrap" && request.method === "POST") return await recoverVault(request, env, identity);
      return json({ error: "not_found" }, 404);
    } catch (error) {
      if (error instanceof HttpError) return json({ error: "request_rejected", message: error.message }, error.status);
      return json({ error: "internal_error", message: "The request could not be completed." }, 500);
    }
  },
};
