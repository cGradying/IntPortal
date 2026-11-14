import type { Card, Deck } from "./api";

export type Entry = { deck: Deck; card: Card };

/** Every card due at `now`, across the decks, oldest due first (spec 040 C9). */
export function dueQueue(decks: Deck[], now: number): Entry[] {
  return decks.flatMap((deck) => deck.cards.filter((c) => c.memory.due <= now).map((card) => ({ deck, card }))).sort((a, b) => a.card.memory.due - b.card.memory.due);
}
