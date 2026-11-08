import { describe, expect, it } from "vitest";
import { readJson } from "../src/index";

describe("bounded JSON request parsing", () => {
  it("parses a JSON object from a streaming request body", async () => {
    const request = new Request("https://aureon.test/v1/vault/snapshot", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ vaultId: "vault-test", generation: 1 }),
    });
    await expect(readJson(request)).resolves.toEqual({
      vaultId: "vault-test",
      generation: 1,
    });
  });

  it("rejects oversized streamed bodies even when Content-Length is absent", async () => {
    const request = new Request("https://aureon.test/v1/vault/snapshot", {
      method: "POST",
      body: JSON.stringify({ payload: "x".repeat(900_100) }),
    });
    await expect(readJson(request)).rejects.toMatchObject({ status: 413 });
  });

  it("rejects invalid Content-Length before consuming the body", async () => {
    const request = new Request("https://aureon.test/v1/vault/snapshot", {
      method: "POST",
      headers: { "content-length": "-1" },
      body: "{}",
    });
    await expect(readJson(request)).rejects.toMatchObject({ status: 400 });
  });

  it("rejects non-object JSON payloads", async () => {
    const request = new Request("https://aureon.test/v1/vault/snapshot", {
      method: "POST",
      body: "[]",
    });
    await expect(readJson(request)).rejects.toMatchObject({ status: 400 });
  });
});
