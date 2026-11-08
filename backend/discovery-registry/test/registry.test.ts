import { describe, expect, it } from "vitest";
import { validateDiscoveryId, validateProfile } from "../src/index";

describe("discovery profile validation", () => {
  it("accepts an opaque high-entropy locator", () => {
    expect(validateDiscoveryId("0123456789abcdefghijklmnopqrstuv0123456789")).toHaveLength(42);
  });
  it("rejects email-like and undersized locators", () => {
    expect(() => validateDiscoveryId("owner@example.com")).toThrow();
    expect(() => validateDiscoveryId("short")).toThrow();
  });
  it("accepts only HTTPS Worker origins", () => {
    const profile = validateProfile({
      firebaseProjectId: "owner-project-123",
      firebaseApiKey: "AIzaSyExamplePublicFirebaseClientKey",
      firebaseAuthDomain: "owner-project-123.firebaseapp.com",
      firebaseAppId: "1:123456789:web:abcdef123456",
      workerBaseUrl: "https://owner-api.example.workers.dev",
    }, "0123456789abcdefghijklmnopqrstuv0123456789");
    expect(profile.workerBaseUrl).toBe("https://owner-api.example.workers.dev");
  });
  it("rejects insecure or path-scoped Worker URLs", () => {
    const base = {
      firebaseProjectId: "owner-project-123",
      firebaseApiKey: "AIzaSyExamplePublicFirebaseClientKey",
      firebaseAuthDomain: "owner-project-123.firebaseapp.com",
      firebaseAppId: "1:123456789:web:abcdef123456",
    };
    expect(() => validateProfile({...base, workerBaseUrl: "http://worker.example"}, "0123456789abcdefghijklmnopqrstuv0123456789")).toThrow();
    expect(() => validateProfile({...base, workerBaseUrl: "https://worker.example/api"}, "0123456789abcdefghijklmnopqrstuv0123456789")).toThrow();
  });
});
