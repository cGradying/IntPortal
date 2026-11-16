/** Whether an ISO date ("2026-11-19") falls in the Monday-to-Sunday week holding `today` (050 C12). */
export function inThisWeek(iso: string | null, today: Date): boolean {
  if (!iso) return false;
  const [y, m, d] = iso.split("-").map(Number);
  const day = new Date(y, m - 1, d);
  const monday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - ((today.getDay() + 6) % 7));
  const next = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 7);
  return day >= monday && day < next;
}
