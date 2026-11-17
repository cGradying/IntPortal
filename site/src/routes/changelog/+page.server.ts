import { parseChangelog } from "$lib/content/changelog";
import md from "../../../../CHANGELOG.md?raw";

/** Spec 057 C12: the repo's CHANGELOG.md, read when the site is built. */
export const load = () => ({ releases: parseChangelog(md) });
