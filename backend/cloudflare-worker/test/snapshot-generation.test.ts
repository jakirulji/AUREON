import { describe, expect, it } from "vitest";
import { canAdvanceSnapshot } from "../src/index";

describe("vault snapshot generation monotonicity", () => {
  it("accepts the first snapshot at any positive generation", () => {
    expect(canAdvanceSnapshot(null, { generation: 4, createdAtEpochMs: 100 })).toBe(true);
  });

  it("accepts a forward generation jump after offline rotations", () => {
    expect(canAdvanceSnapshot(
      { generation: 2, created_at_ms: 500 },
      { generation: 5, createdAtEpochMs: 100 },
    )).toBe(true);
  });

  it("rejects rollback and same-generation stale timestamps", () => {
    const current = { generation: 5, created_at_ms: 900 };
    expect(canAdvanceSnapshot(current, { generation: 4, createdAtEpochMs: 1000 })).toBe(false);
    expect(canAdvanceSnapshot(current, { generation: 5, createdAtEpochMs: 900 })).toBe(false);
    expect(canAdvanceSnapshot(current, { generation: 5, createdAtEpochMs: 899 })).toBe(false);
  });

  it("accepts only a strictly newer snapshot within the same generation", () => {
    expect(canAdvanceSnapshot(
      { generation: 5, created_at_ms: 900 },
      { generation: 5, createdAtEpochMs: 901 },
    )).toBe(true);
  });
});
