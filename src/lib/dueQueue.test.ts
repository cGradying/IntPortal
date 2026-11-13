import { describe, expect, it } from "vitest";
import type { Card, Deck } from "./api";
import { dueQueue } from "./dueQueue";

const card = (id: string, due: number) => ({ id, memory: { due } }) as unknown as Card;
const deck = (id: string, cards: Card[]) => ({ id, name: id, subject: null, cards }) as unknown as Deck;

describe("spec 040 C9/C10: Due now", () => {
  it("c9_due_cards_across_decks_oldest_first", () => {
    const q = dueQueue([deck("a", [card("a1", 30), card("a2", 500)]), deck("b", [card("b1", 10), card("b2", 20)])], 100);
    expect(q.map((e) => e.card.id)).toEqual(["b1", "b2", "a1"]);
    expect(q.map((e) => e.deck.id)).toEqual(["b", "b", "a"]);
  });
  it("with one deck due the queue is still oldest first and carries its deck", () => {
    const q = dueQueue([deck("a", [card("a1", 50), card("a2", 5)]), deck("b", [card("b1", 900)])], 100);
    expect(q.map((e) => [e.deck.id, e.card.id])).toEqual([["a", "a2"], ["a", "a1"]]);
  });
});
