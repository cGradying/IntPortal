import { describe, expect, it } from "vitest";
import { leave } from "./leave";

describe("spec 040 C1", () => {
  it("c1_notes_tab_saves_first", async () => {
    const log: string[] = [];
    await leave(true, async () => (log.push("save"), true), () => log.push("open notes"));
    expect(log).toEqual(["save", "open notes"]);
  });
  it("a clean page just leaves; a failed save stays", async () => {
    const log: string[] = [];
    await leave(false, async () => (log.push("save"), true), () => log.push("left"));
    expect(await leave(true, async () => false, () => log.push("never"))).toBe(false);
    expect(log).toEqual(["left"]);
  });
});
