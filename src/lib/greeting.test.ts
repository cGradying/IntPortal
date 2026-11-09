import { describe, expect, it } from "vitest";
import { greeting, helloTimes } from "./greeting";

const at = (h: number) => new Date(2026, 10, 9, h, 30);

describe("the launch hello (spec 010 C35)", () => {
  it("c35_says_the_part_of_day", () => {
    expect(greeting(at(3))).toBe("Up late");
    expect(greeting(at(9))).toBe("Good morning");
    expect(greeting(at(14))).toBe("Good afternoon");
    expect(greeting(at(20))).toBe("Good evening");
  });

  it("c35_lines_arrive_in_order_then_hold", () => {
    expect(helloTimes(false)).toEqual({ in: [0, 450], hold: 1500, out: 500 });
  });

  it("c35_reduce_motion_is_one_short_cross_fade", () => {
    const t = helloTimes(true);
    expect(new Set(t.in).size).toBe(1);
    expect(t.out).toBeLessThanOrEqual(300);
  });
});
