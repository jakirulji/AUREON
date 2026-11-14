import { describe, expect, it } from "vitest";
import { validateDriveConnectionSlots } from "../src/index";

describe("Master Account Drive connection slots", () => {
  it("accepts only user-created labels, opaque slot IDs and ordering", () => {
    expect(validateDriveConnectionSlots([
      { slotId: "slot_123456789012345678", label: "  Personal Drive  ", sortOrder: 0 },
      { slotId: "slot_abcdefghijklmno1234", label: "Archive", sortOrder: 1 },
    ])).toEqual([
      { slotId: "slot_123456789012345678", label: "Personal Drive", sortOrder: 0 },
      { slotId: "slot_abcdefghijklmno1234", label: "Archive", sortOrder: 1 },
    ]);
  });

  it("rejects Google identity, OAuth token and Drive metadata fields", () => {
    expect(() => validateDriveConnectionSlots([
      { slotId: "slot_123456789012345678", label: "Personal", sortOrder: 0, email: "person@gmail.com" },
    ])).toThrow(/only slotId, label and sortOrder/);
    expect(() => validateDriveConnectionSlots([
      { slotId: "slot_123456789012345678", label: "Personal", sortOrder: 0, accessToken: "secret" },
    ])).toThrow(/only slotId, label and sortOrder/);
  });

  it("rejects duplicates, invalid ordering and oversized registries", () => {
    expect(() => validateDriveConnectionSlots([
      { slotId: "slot_123456789012345678", label: "A", sortOrder: 0 },
      { slotId: "slot_123456789012345678", label: "B", sortOrder: 1 },
    ])).toThrow(/invalid or duplicated/);
    expect(() => validateDriveConnectionSlots([
      { slotId: "slot_123456789012345678", label: "A", sortOrder: 20 },
    ])).toThrow(/order/);
    expect(() => validateDriveConnectionSlots(Array.from({ length: 21 }, (_, i) => ({
      slotId: `slot_${String(i).padStart(18, "0")}`, label: `Slot ${i}`, sortOrder: i,
    })))).toThrow(/count/);
  });

  it("accepts an empty list to remove every slot for the authenticated owner", () => {
    expect(validateDriveConnectionSlots([])).toEqual([]);
  });
});
