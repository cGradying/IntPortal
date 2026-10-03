import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const impactFeedback = vi.fn(() => Promise.resolve());
const notificationFeedback = vi.fn(() => Promise.resolve());
const selectionFeedback = vi.fn(() => Promise.resolve());
vi.mock("@tauri-apps/plugin-haptics", () => ({ impactFeedback, notificationFeedback, selectionFeedback }));

const { buzz, haptics } = await import("./haptics");

describe("buzz", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    vi.advanceTimersByTime(1000);
    haptics.on = true;
  });
  afterEach(() => vi.useRealTimers());

  it("speaks each verb with its own feel", () => {
    for (const verb of ["select", "tick", "press", "pull", "release", "done", "warn", "fail"] as const) {
      buzz[verb]();
      vi.advanceTimersByTime(100);
    }
    expect(impactFeedback.mock.calls.map((c) => (c as unknown[])[0])).toEqual(["rigid", "medium", "soft", "light"]);
    expect(notificationFeedback.mock.calls.map((c) => (c as unknown[])[0])).toEqual(["success", "warning", "error"]);
    expect(selectionFeedback).toHaveBeenCalledOnce();
  });

  it("drops a second buzz that would land on top of the first", () => {
    buzz.tick();
    vi.advanceTimersByTime(20);
    buzz.tick();
    expect(impactFeedback).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(40);
    buzz.tick();
    expect(impactFeedback).toHaveBeenCalledTimes(2);
  });

  it("stays silent when the student turns haptics off", () => {
    haptics.on = false;
    buzz.done();
    buzz.select();
    expect(notificationFeedback).not.toHaveBeenCalled();
    expect(selectionFeedback).not.toHaveBeenCalled();
  });
});
