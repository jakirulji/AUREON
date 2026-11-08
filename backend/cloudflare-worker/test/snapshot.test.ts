import { describe, expect, it } from "vitest";
import { validateSnapshot } from "../src/index";

function b64(bytes: number[]): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function envelope(keyId: string) {
  return { keyId, salt: b64(Array(32).fill(1)), nonce: b64(Array(12).fill(2)),
    cipherText: b64(Array(32).fill(3)), mac: b64(Array(16).fill(4)) };
}
function validSnapshot() {
  return { format: "AUREON-VAULT-RECOVERY-BUNDLE", formatVersion: 1,
    vaultId: "vault-test", generation: 1, createdAtEpochMs: 1_800_000_000_000,
    encryptedCredentialRecords: [{ formatVersion: 1, providerAccountId: "google-subject-1",
      recordVersion: 1, cipher: "AES-256-GCM", nonce: b64(Array(12).fill(5)),
      cipherText: b64([6, 7, 8]), mac: b64(Array(16).fill(9)) }],
    manualKeyEnvelopes: ["key-1", "key-2", "key-3", "key-4", "key-5"].map(envelope),
    cloudflareEnvelope: { formatVersion: 1, algorithm: "HKDF-SHA-256/AES-256-GCM",
      salt: b64(Array(32).fill(10)), nonce: b64(Array(12).fill(11)), cipherText: b64(Array(48).fill(12)) } };
}

describe("vault snapshot validation", () => {
  it("accepts a valid encrypted snapshot with exactly five independent envelope IDs", () => {
    const result = validateSnapshot(validSnapshot());
    expect(result.vaultId).toBe("vault-test");
    expect(result.manualKeyEnvelopes).toHaveLength(5);
  });
  it("rejects duplicate manual key IDs", () => {
    const input = validSnapshot();
    input.manualKeyEnvelopes[4] = envelope("key-1");
    expect(() => validateSnapshot(input)).toThrow(/Duplicate manual key ID/);
  });
  it("rejects plaintext OAuth credentials", () => {
    const input = validSnapshot();
    input.encryptedCredentialRecords[0].refreshToken = "must-never-be-stored";
    expect(() => validateSnapshot(input)).toThrow(/Plaintext secret field/);
  });
  it("rejects malformed AES-GCM nonce lengths", () => {
    const input = validSnapshot();
    input.encryptedCredentialRecords[0].nonce = b64([1, 2, 3]);
    expect(() => validateSnapshot(input)).toThrow(/cryptographic fields/);
  });
  it("rejects duplicate provider account records", () => {
    const input = validSnapshot();
    input.encryptedCredentialRecords.push({ ...input.encryptedCredentialRecords[0] });
    expect(() => validateSnapshot(input)).toThrow(/Duplicate provider account/);
  });
  it("rejects a bundle without all five manual envelopes", () => {
    const input = validSnapshot();
    input.manualKeyEnvelopes.pop();
    expect(() => validateSnapshot(input)).toThrow(/Exactly five/);
  });
});
