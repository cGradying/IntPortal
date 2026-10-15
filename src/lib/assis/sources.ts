// Where a source chip under one of LAR's answers leads. Keys come from the
// index in the core: `card:<deck id>`, `plan:<subject code>`, else a note.
export type SourceTarget = { kind: "deck"; id: string } | { kind: "subject"; code: string } | { kind: "note" };

export function sourceTarget(key: string): SourceTarget {
  if (key.startsWith("card:") && key.length > 5) return { kind: "deck", id: key.slice(5) };
  if (key.startsWith("plan:") && key.length > 5) return { kind: "subject", code: key.slice(5) };
  return { kind: "note" };
}
