import { describe, expect, it } from "vitest";
import { createCloudflareEnvelope, unwrapAndRewrap } from "../src/index";

function bytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0));
}
function arrayBuffer(value: Uint8Array): ArrayBuffer {
  const result = new ArrayBuffer(value.length);
  new Uint8Array(result).set(value);
  return result;
}
function encode(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

describe("Cloudflare vault envelope cryptographic interoperability", () => {
  it("wraps the DEK under the Worker secret and rewraps it to an ephemeral P-256 device key", async () => {
    const root = new Uint8Array(32).fill(41);
    const env = {
      DB: {} as D1Database,
      FIREBASE_PROJECT_ID: "aureon-test",
      AUREON_VAULT_ROOT_SECRET_V1: encode(root),
      AUREON_VAULT_ACTIVE_ROOT_VERSION: "1",
    } as Parameters<typeof createCloudflareEnvelope>[3];
    const vaultId = "vault-crypto-interoperability";
    const generation = 4;
    const expectedDek = new Uint8Array(Array.from({ length: 32 }, (_, index) => index + 1));
    const wrapped = await createCloudflareEnvelope(expectedDek.slice(), vaultId, generation, env);

    const device = await crypto.subtle.generateKey(
      { name: "ECDH", namedCurve: "P-256" },
      true,
      ["deriveBits"],
    );
    const devicePublicJwk = await crypto.subtle.exportKey("jwk", device.publicKey);
    const response = await unwrapAndRewrap(wrapped, vaultId, generation, devicePublicJwk, env);

    expect(response.algorithm).toBe("ECDH-P256/HKDF-SHA-256/AES-256-GCM");
    expect(response.generation).toBe(generation);
    const serverPublic = await crypto.subtle.importKey(
      "jwk",
      response.serverEphemeralPublicKey,
      { name: "ECDH", namedCurve: "P-256" },
      false,
      [],
    );
    const shared = new Uint8Array(await crypto.subtle.deriveBits(
      { name: "ECDH", public: serverPublic },
      device.privateKey,
      256,
    ));
    const salt = bytes(response.salt);
    const nonce = bytes(response.nonce);
    const combined = bytes(response.cipherText);
    const info = new TextEncoder().encode(`AUREON|DEVICE-BOUND-VAULT-DEK|v1|${vaultId}|${generation}`);
    const material = await crypto.subtle.importKey("raw", arrayBuffer(shared), "HKDF", false, ["deriveKey"]);
    shared.fill(0);
    const key = await crypto.subtle.deriveKey(
      { name: "HKDF", hash: "SHA-256", salt: arrayBuffer(salt), info: arrayBuffer(info) },
      material,
      { name: "AES-GCM", length: 256 },
      false,
      ["decrypt"],
    );
    const clear = new Uint8Array(await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: arrayBuffer(nonce), additionalData: arrayBuffer(info), tagLength: 128 },
      key,
      arrayBuffer(combined),
    ));
    expect([...clear]).toEqual([...expectedDek]);
    clear.fill(0);
  });

  it("keeps old envelope versions decryptable while the new root version is active", async () => {
    const rootV1 = new Uint8Array(32).fill(51);
    const rootV2 = new Uint8Array(32).fill(52);
    const initialEnv = {
      DB: {} as D1Database,
      FIREBASE_PROJECT_ID: "aureon-test",
      AUREON_VAULT_ROOT_SECRET_V1: encode(rootV1),
      AUREON_VAULT_ACTIVE_ROOT_VERSION: "1",
    } as Parameters<typeof createCloudflareEnvelope>[3];
    const dek = new Uint8Array(32).fill(19);
    const oldEnvelope = await createCloudflareEnvelope(dek.slice(), "vault-key-version", 1, initialEnv);
    const rotatedEnv = {
      ...initialEnv,
      AUREON_VAULT_ROOT_SECRET_V2: encode(rootV2),
      AUREON_VAULT_ACTIVE_ROOT_VERSION: "2",
    } as Parameters<typeof createCloudflareEnvelope>[3];
    const newEnvelope = await createCloudflareEnvelope(dek.slice(), "vault-key-version", 2, rotatedEnv);
    expect(oldEnvelope.rootKeyVersion).toBe(1);
    expect(newEnvelope.rootKeyVersion).toBe(2);
    const device = await crypto.subtle.generateKey(
      { name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"],
    );
    const publicJwk = await crypto.subtle.exportKey("jwk", device.publicKey);
    await expect(unwrapAndRewrap(oldEnvelope, "vault-key-version", 1, publicJwk, rotatedEnv)).resolves.toBeDefined();
    await expect(unwrapAndRewrap(newEnvelope, "vault-key-version", 2, publicJwk, rotatedEnv)).resolves.toBeDefined();
  });
});
