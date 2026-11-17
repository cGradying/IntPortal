// Just enough Markdown for PRIVACY.md: headings, paragraphs, lists, tables,
// bold, code and links. Everything is escaped first.
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export function inline(s: string): string {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/&lt;(https:\/\/[^&\s]+)&gt;/g, '<a href="$1" rel="noopener">$1</a>')
    .replace(/\[([^\]]+)\]\((https:\/\/[^)\s]+)\)/g, '<a href="$2" rel="noopener">$1</a>');
}

export function markdown(text: string): string {
  const out: string[] = [];
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    const h = l.match(/^(#{1,3}) (.*)$/);
    if (h) out.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`);
    else if (l.startsWith("- ")) {
      const items: string[] = [];
      for (; i < lines.length && lines[i].startsWith("- "); i++) items.push(`<li>${inline(lines[i].slice(2))}</li>`);
      i--;
      out.push(`<ul>${items.join("")}</ul>`);
    } else if (l.startsWith("|")) {
      const rows: string[][] = [];
      for (; i < lines.length && lines[i].startsWith("|"); i++) rows.push(lines[i].slice(1, -1).split("|").map((c) => c.trim()));
      i--;
      const [head, , ...body] = rows;
      out.push(`<div class="table"><table><thead><tr>${head.map((c) => `<th>${inline(c)}</th>`).join("")}</tr></thead><tbody>${body.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`);
    } else if (l.trim()) out.push(`<p>${inline(l)}</p>`);
  }
  return out.join("\n");
}
