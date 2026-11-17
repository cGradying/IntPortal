// PLACEHOLDER until #326 lands.
import type { RoadItem } from "$lib/content/types";
const S = "https://github.com/cGradying/IntPortal/blob/main/docs/specs/";
export const load = () => ({
  items: [
    { title: "0.4.0", line: "IntPortal on every platform.", lane: "shipped", href: "/changelog#v0.4.0", kind: "release", date: "2026-11-17" },
    { title: "Website, second edition", line: "This site.", lane: "building", href: S + "057-website-v2.md", kind: "spec" },
    { title: "IntAssis 2", line: "A better on-device assistant.", lane: "building", href: S + "021-intassis-v2.md", kind: "spec" },
    { title: "Accessibility pass", line: "Every screen checked.", lane: "next", href: "https://github.com/cGradying/IntPortal/issues/66", kind: "issue" },
    { title: "The web app", line: "Signed in, in any browser.", lane: "later", href: S + "056-web-app.md", kind: "spec" },
  ] as RoadItem[],
});
