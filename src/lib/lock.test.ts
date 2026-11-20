import { expect, it, vi } from "vitest";

vi.mock("@tauri-apps/plugin-biometric", () => ({ authenticate: vi.fn(async () => {}), checkStatus: vi.fn() }));
vi.mock("./haptics", () => ({ buzz: { done: () => {} } }));

import { lock, unlock, whenUnlocked } from "./lock.svelte";

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
