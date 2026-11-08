import { createRemoteJWKSet, jwtVerify } from "jose";

interface RateLimitBinding { limit(input: { key: string }): Promise<{ success: boolean }> }
interface Env {
  DB: D1Database;
  REGISTRY_RATE_LIMITER?: RateLimitBinding;
}
interface PublicProfile {
  accountRecoveryId: string;
  firebaseProjectId: string;
  firebaseApiKey: string;
  firebaseAuthDomain: string;
  firebaseAppId: string;
  workerBaseUrl: string;
  profileVersion: number;
}
interface OwnerIdentity { issuer: string; uid: string }
const FIREBASE_JWKS = createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"));
const MAX_BODY_BYTES = 16 * 1024;
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "access-control-allow-origin": "*" };

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}
function requiredString(value: unknown, field: string, min = 1, max = 512): string {
  if (typeof value !== "string" || value.trim().length < min || value.trim().length > max) {
    throw new HttpError(400, `Invalid ${field}.`);
  }
  return value.trim();
}
export function validateAccountRecoveryId(value: unknown): string {
  const id = requiredString(value, "Account Recovery ID", 22, 128);
  if (!/^[A-Za-z0-9_-]+$/.test(id)) throw new HttpError(400, "Invalid Account Recovery ID.");
  return id;
}
async function readJson(request: Request): Promise<Record<string, unknown>> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY_BYTES) throw new HttpError(413, "Request body is too large.");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) throw new HttpError(413, "Request body is too large.");
  let value: unknown;
  try { value = JSON.parse(raw); } catch { throw new HttpError(400, "Invalid JSON."); }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpError(400, "A JSON object is required.");
  return value as Record<string, unknown>;
}
async function sha256Hex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
export function validateProfile(body: Record<string, unknown>, accountRecoveryId: string): PublicProfile {
  const firebaseProjectId = requiredString(body.firebaseProjectId, "Firebase project ID", 1, 128);
  if (!/^[a-z0-9-]+$/.test(firebaseProjectId)) throw new HttpError(400, "Invalid Firebase project ID.");
  const firebaseApiKey = requiredString(body.firebaseApiKey, "Firebase API key", 20, 256);
  const firebaseAuthDomain = requiredString(body.firebaseAuthDomain, "Firebase auth domain", 3, 253);
  const firebaseAppId = requiredString(body.firebaseAppId, "Firebase app ID", 3, 256);
  const workerRaw = requiredString(body.workerBaseUrl, "Cloudflare Worker URL", 10, 512);
  let worker: URL;
  try { worker = new URL(workerRaw); } catch { throw new HttpError(400, "Invalid Cloudflare Worker URL."); }
  if (worker.protocol !== "https:" || worker.username || worker.password || worker.search || worker.hash ||
      (worker.pathname !== "/" && worker.pathname !== "")) {
    throw new HttpError(400, "Cloudflare Worker URL must be an HTTPS origin without path, credentials, query or fragment.");
  }
  return { accountRecoveryId, firebaseProjectId, firebaseApiKey, firebaseAuthDomain,
    firebaseAppId, workerBaseUrl: worker.origin, profileVersion: 1 };
}
async function authenticate(request: Request, projectId: string): Promise<OwnerIdentity> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new HttpError(401, "Authentication required.");
  try {
    const { payload } = await jwtVerify(authorization.slice(7), FIREBASE_JWKS, {
      issuer: `https://securetoken.google.com/${projectId}`, audience: projectId,
      algorithms: ["RS256"],
    });
    if (payload.email_verified !== true || typeof payload.sub !== "string" || !payload.sub ||
        typeof payload.iss !== "string") throw new HttpError(403, "A verified Firebase account is required.");
    return { issuer: payload.iss, uid: payload.sub };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(401, "Firebase identity token is invalid or expired.");
  }
}
async function rateLimit(request: Request, env: Env): Promise<void> {
  const ip = request.headers.get("cf-connecting-ip");
  if (!ip || !env.REGISTRY_RATE_LIMITER) throw new HttpError(503, "Discovery rate limiting is not configured.");
  const result = await env.REGISTRY_RATE_LIMITER.limit({ key: ip });
  if (!result.success) throw new HttpError(429, "Too many discovery requests. Try again later.");
}
async function lookup(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const id = validateAccountRecoveryId(body.accountRecoveryId);
  const hash = await sha256Hex(id);
  const row = await env.DB.prepare("SELECT firebase_project_id,firebase_api_key,firebase_auth_domain,firebase_app_id,worker_base_url,profile_version FROM discovery_profiles WHERE account_recovery_id_hash=?")
    .bind(hash).first<{ firebase_project_id: string; firebase_api_key: string; firebase_auth_domain: string; firebase_app_id: string; worker_base_url: string; profile_version: number }>();
  if (!row) return response({ error: "profile_not_found" }, 404);
  return response({ profile: {
    accountRecoveryId: id, firebaseProjectId: row.firebase_project_id, firebaseApiKey: row.firebase_api_key,
    firebaseAuthDomain: row.firebase_auth_domain, firebaseAppId: row.firebase_app_id,
    workerBaseUrl: row.worker_base_url, profileVersion: row.profile_version,
  } });
}
async function register(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const id = validateAccountRecoveryId(body.accountRecoveryId);
  const profile = validateProfile(body, id);
  const identity = await authenticate(request, profile.firebaseProjectId);
  const hash = await sha256Hex(id), now = Date.now();
  const existing = await env.DB.prepare("SELECT firebase_issuer,firebase_uid,profile_version FROM discovery_profiles WHERE account_recovery_id_hash=?")
    .bind(hash).first<{ firebase_issuer: string; firebase_uid: string; profile_version: number }>();
  if (!existing) {
    try {
      const result = await env.DB.prepare("INSERT INTO discovery_profiles (account_recovery_id_hash,firebase_project_id,firebase_api_key,firebase_auth_domain,firebase_app_id,worker_base_url,firebase_issuer,firebase_uid,profile_version,created_at_ms,updated_at_ms) VALUES (?,?,?,?,?,?,?,?,1,?,?)")
        .bind(hash, profile.firebaseProjectId, profile.firebaseApiKey, profile.firebaseAuthDomain, profile.firebaseAppId,
          profile.workerBaseUrl, identity.issuer, identity.uid, now, now).run();
      if (!result.success || result.meta.changes !== 1) {
        throw new HttpError(409, "Account Recovery ID reservation conflicted; generate a new ID and retry.");
      }
    } catch (error) {
      if (error instanceof HttpError) throw error;
      // The database primary key is the final uniqueness guard. A concurrent
      // insert of the same hashed locator must never overwrite another owner.
      throw new HttpError(409, "Account Recovery ID is already reserved; generate a new ID and retry.");
    }
    return response({ registered: true, profileVersion: 1 }, 201);
  }
  if (existing.firebase_issuer !== identity.issuer || existing.firebase_uid !== identity.uid) {
    throw new HttpError(409, "Account Recovery ID is already bound to another Master Account.");
  }
  const expected = body.expectedProfileVersion;
  if (!Number.isSafeInteger(expected) || expected !== existing.profile_version) {
    throw new HttpError(409, "Profile changed on another device. Refresh it before updating.");
  }
  const nextVersion = existing.profile_version + 1;
  const result = await env.DB.prepare("UPDATE discovery_profiles SET firebase_project_id=?,firebase_api_key=?,firebase_auth_domain=?,firebase_app_id=?,worker_base_url=?,profile_version=?,updated_at_ms=? WHERE account_recovery_id_hash=? AND firebase_issuer=? AND firebase_uid=? AND profile_version=?")
    .bind(profile.firebaseProjectId, profile.firebaseApiKey, profile.firebaseAuthDomain, profile.firebaseAppId,
      profile.workerBaseUrl, nextVersion, now, hash, identity.issuer, identity.uid, existing.profile_version).run();
  if (!result.success || result.meta.changes !== 1) throw new HttpError(409, "Profile update conflicted; reload and retry.");
  return response({ registered: false, profileVersion: nextVersion });
}
async function verifyBinding(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const id = validateAccountRecoveryId(body.accountRecoveryId);
  const projectId = requiredString(body.firebaseProjectId, "Firebase project ID", 1, 128);
  const identity = await authenticate(request, projectId);
  const hash = await sha256Hex(id);
  const row = await env.DB.prepare("SELECT firebase_issuer,firebase_uid FROM discovery_profiles WHERE account_recovery_id_hash=?")
    .bind(hash).first<{ firebase_issuer: string; firebase_uid: string }>();
  if (!row || row.firebase_issuer !== identity.issuer || row.firebase_uid !== identity.uid) {
    throw new HttpError(403, "Master Account does not match this Account Recovery ID.");
  }
  return response({ bound: true });
}
async function unregister(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const id = validateAccountRecoveryId(body.accountRecoveryId);
  const projectId = requiredString(body.firebaseProjectId, "Firebase project ID", 1, 128);
  const identity = await authenticate(request, projectId);
  const hash = await sha256Hex(id);
  const result = await env.DB.prepare("DELETE FROM discovery_profiles WHERE account_recovery_id_hash=? AND firebase_issuer=? AND firebase_uid=?")
    .bind(hash, identity.issuer, identity.uid).run();
  if (!result.success) throw new HttpError(503, "Profile removal failed.");
  return response({ removed: result.meta.changes === 1 });
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "POST,PUT,DELETE,OPTIONS", "access-control-allow-headers": "authorization,content-type", "access-control-max-age": "86400" } });
    try {
      if (url.pathname === "/health/live" && request.method === "GET") return response({ status: "ok" });
      if (url.pathname === "/v1/profiles/lookup" && request.method === "POST") {
        await rateLimit(request, env);
        return await lookup(request, env);
      }
      if (url.pathname === "/v1/profiles/verify" && request.method === "POST") {
        await rateLimit(request, env);
        return await verifyBinding(request, env);
      }
      if (url.pathname === "/v1/profiles" && request.method === "POST") {
        await rateLimit(request, env);
        return await register(request, env);
      }
      if (url.pathname === "/v1/profiles" && request.method === "DELETE") {
        await rateLimit(request, env);
        return await unregister(request, env);
      }
      return response({ error: "not_found" }, 404);
    } catch (error) {
      if (error instanceof HttpError) return response({ error: "request_rejected", message: error.message }, error.status);
      return response({ error: "internal_error", message: "The discovery request could not be completed." }, 500);
    }
  },
};
