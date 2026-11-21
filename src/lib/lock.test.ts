import { expect, it, vi } from "vitest";

vi.mock("@tauri-apps/plugin-biometric", () => ({ authenticate: vi.fn(async () => {}), checkStatus: vi.fn() }));
vi.mock("./haptics", () => ({ buzz: { done: () => {} } }));

import { lock, unlock, watchLock, whenUnlocked } from "./lock.svelte";

it("a notification tapped while locked opens only after unlocking", async () => {
  lock.locked = true;
  const open = vi.fn();
  whenUnlocked(open);
  expect(open).not.toHaveBeenCalled();
  await unlock();
  expect(open).toHaveBeenCalledOnce();
  whenUnlocked(open);
  expect(open).toHaveBeenCalledTimes(2);
});

it("a tap that arrives before the app notices it was away still waits for unlock", async () => {
  lock.enabled = true;
  lock.locked = false;
  // No DOM in these tests: a bare event target stands in for the document.
  const doc = Object.assign(new EventTarget(), { hidden: true });
  vi.stubGlobal("document", doc);
  watchLock();
  const now = Date.now();
  vi.spyOn(Date, "now").mockReturnValue(now);
  doc.dispatchEvent(new Event("visibilitychange"));
  vi.spyOn(Date, "now").mockReturnValue(now + 61_000);
  const open = vi.fn();
  whenUnlocked(open);
  expect(lock.locked).toBe(true);
  expect(open).not.toHaveBeenCalled();
  await unlock();
  expect(open).toHaveBeenCalledOnce();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
