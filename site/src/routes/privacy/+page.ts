import text from "../../../../PRIVACY.md?raw";
import { markdown } from "$lib/markdown";

/** PRIVACY.md is the one privacy text; the site renders it (051 C5). */
export const load = () => ({ html: markdown(text) });
