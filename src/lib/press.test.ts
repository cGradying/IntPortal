import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { HOLD_MS, pressTimer } from "./press";

describe("pressTimer", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("fires after a still hold and swallows the click that follows", () => {
    const long = vi.fn();
    const p = pressTimer(long);
    p.down(10, 10);
    vi.advanceTimersByTime(HOLD_MS - 1);
    expect(long).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(long).toHaveBeenCalledOnce();
    expect(p.up()).toBe(true);
  });

  it("is a plain tap when let go early", () => {
    const long = vi.fn();
    const p = pressTimer(long);
    p.down(10, 10);
    vi.advanceTimersByTime(200);
    expect(p.up()).toBe(false);
    vi.advanceTimersByTime(HOLD_MS);
    expect(long).not.toHaveBeenCalled();
  });

  it("gives way to a scroll or swipe", () => {
    const long = vi.fn();
    const p = pressTimer(long);
    p.down(10, 10);
    p.move(10, 22);
    vi.advanceTimersByTime(HOLD_MS);
    expect(long).not.toHaveBeenCalled();
    expect(p.up()).toBe(false);
  });

  it("ignores a finger that only trembles", () => {
    const long = vi.fn();
    const p = pressTimer(long);
    p.down(10, 10);
    p.move(13, 12);
    vi.advanceTimersByTime(HOLD_MS);
    expect(long).toHaveBeenCalledOnce();
  });
});
