import { beforeEach, describe, expect, it, vi } from "vitest";

const backend: Record<string, (args: any) => unknown> = {};
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async (cmd: string, args?: any) => {
    const h = backend[cmd];
    if (!h) throw new Error(`no handler for ${cmd}`);
    return h(args);
  }),
}));
vi.mock("@tauri-apps/plugin-notification", () => ({
  Schedule: { at: (d: Date) => ({ at: d }) },
  cancel: vi.fn(),
  isPermissionGranted: vi.fn(),
  onAction: vi.fn(),
  pending: vi.fn(),
  requestPermission: vi.fn(),
}));

import { app, openFromNotification } from "./state.svelte";

describe("spec 042 C7, C9: a tapped notification opens what it is about", () => {
  beforeEach(() => {
    app.tab = "schedule";
    app.deck = null;
    app.editing = null;
    app.snapshot = { sessions: [{ subject_code: "COMP 20073", description: "Data Structures" }] } as any;
    backend.study = () => ({
      decks: [
        { id: "d0", name: "Old", subject: "COMP 20073", cards: 4, due: 0 },
        { id: "d1", name: "Trees", subject: "COMP 20073", cards: 9, due: 6 },
      ],
      due: 6,
      streak: 0,
      reviews_today: 0,
    });
  });

  it("c7_warm_up_starts_a_five_card_session_on_that_subjects_due_deck", async () => {
    await openFromNotification("study:COMP 20073:5");
    expect([app.tab, app.deck, app.review]).toEqual(["study", null, { subject: "COMP 20073", limit: 5 }]);
  });

  it("a study link without a count opens the deck page", async () => {
    await openFromNotification("study:COMP 20073");
    expect([app.tab, app.deck]).toEqual(["study", "d1"]);
  });

  it("c14a_after_class_opens_the_entry", async () => {
    await openFromNotification("note:class:COMP 20073");
    expect(app.editing).toEqual({ key: "class:COMP 20073", heading: "COMP 20073", title: "Data Structures", entry: true });
  });

  it("anything else, or a deck that is gone, lands on Today", async () => {
    await openFromNotification(undefined);
    expect(app.tab).toBe("today");
    app.tab = "schedule";
    await openFromNotification("study:GEED 10053:5");
    // Study is asked to review it and tells the student nothing is due.
    expect([app.tab, app.deck, app.review]).toEqual(["study", null, { subject: "GEED 10053", limit: 5 }]);
  });
});
