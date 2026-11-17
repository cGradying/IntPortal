import { describe, expect, it } from "vitest";
import { clockSecs, fresh, mult, play, QUICK_BONUS, requeue, toNext } from "./game";

describe("spec 055 game rules", () => {
  it("c3_multiplier_tiers_at_3_6_10", () => {
    expect([0, 2, 3, 5, 6, 9, 10, 40].map(mult)).toEqual([1, 1, 2, 2, 3, 3, 4, 4]);
    expect(toNext(0)).toEqual({ need: 3, frac: 0 });
    expect(toNext(4)).toEqual({ need: 2, frac: 1 / 3 });
    expect(toNext(10)).toBeNull();
  });

  it("c3_right_scores_ten_times_multiplier_and_counts_tier_up", () => {
    let r = fresh();
    const pts: number[] = [];
    let ups = 0;
    for (let i = 0; i < 3; i++) {
      const p = play(r, "right", 6, "flash");
      r = p.run;
      pts.push(p.points);
      if (p.tierUp) ups++;
    }
    expect(pts).toEqual([10, 10, 20]);
    expect(ups).toBe(1);
    expect(r.score).toBe(40);
  });

  it("c4_hard_keeps_combo_scores_nothing; miss_resets_combo_and_heat", () => {
    let r = { ...fresh(), streak: 5, heat: 2 };
    const h = play(r, "hard", 5, "choice");
    expect(h.run.streak).toBe(5);
    expect(h.points).toBe(0);
    r = play(h.run, "miss", 1, "choice").run;
    expect(r.streak).toBe(0);
    expect(r.heat).toBe(0);
    expect(r.top).toBe(5);
    expect(r.tries).toBe(2);
    expect(r.rights).toBe(1);
  });

  it("c6_quick_answer_adds_bonus_and_heat; slow_cools; running_out_is_not_a_miss", () => {
    const q = play(fresh(), "right", clockSecs("flash") / 2, "flash");
    expect(q.quick).toBe(true);
    expect(q.points).toBe(10 + QUICK_BONUS);
    expect(q.run.heat).toBe(1);
    const slow = play({ ...fresh(), heat: 2 }, "right", clockSecs("type") + 1, "type");
    expect(slow.quick).toBe(false);
    expect(slow.run.heat).toBe(1);
    expect(slow.run.streak).toBe(1);
    expect(play({ ...fresh(), heat: 3 }, "right", 1, "choice").run.heat).toBe(3);
  });

  it("c5_missed_card_comes_back_three_cards_later", () => {
    expect(requeue(["a", "b", "c", "d", "e", "f"], 0, "a")).toEqual(["a", "b", "c", "d", "a", "e", "f"]);
    expect(requeue(["a", "b"], 1, "b")).toEqual(["a", "b", "b"]);
  });
});
