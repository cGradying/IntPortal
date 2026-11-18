// Changelog lines as HTML (057 C12): the changelog's own Markdown, and every "#317"
// in plain text becomes a link to that pull request. Tags, existing links and
// entities such as &#39; are left alone.
import { inline } from "./markdown";
import { REPO_URL } from "./releases";

export function notes(s: string): string {
  let inA = false;
  return inline(s)
    .split(/(<[^>]+>)/)
    .map((part) => {
      if (part.startsWith("<")) {
        if (/^<a\b/.test(part)) inA = true;
        else if (part === "</a>") inA = false;
        return part;
      }
      return inA ? part : part.replace(/(?<!&)#(\d+)\b/g, `<a href="${REPO_URL}/pull/$1" rel="noopener">#$1</a>`);
    })
    .join("");
}
