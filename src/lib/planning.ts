// Spec 042: small decisions behind LAR's plan, kept pure so they can be tested.

/** C4, C7: which decks a review starts from: the due ones, one subject's when named. */
export const dueDecks = <D extends { subject: string | null; due: number }>(decks: D[], subject: string | null): D[] =>
  decks.filter((d) => d.due > 0 && (subject === null || d.subject === subject));

/** C16: reminders are worth scheduling when any switch is on, extras included.
 *  The warm-up rides class reminders (the core adds it only to those), so alone it is silence. */
export const anyReminderOn = (p: { lead: number; deadlineAt: number; studyAt: number; warmUp: boolean; afterClass: boolean; brief: boolean }) =>
  p.lead > 0 || p.deadlineAt >= 0 || p.studyAt >= 0 || p.afterClass || p.brief;
