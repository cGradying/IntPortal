// Spec 058 C4: the search index, prerendered to one JSON file and fetched the
// first time the search opens, so no page carries it.
import { json } from "@sveltejs/kit";
import { FAQ, FIXES } from "$lib/content/help";
import { FEATURES, GROUPS } from "$lib/content/features";
import { parseChangelog } from "$lib/content/changelog";
import { buildIndex } from "$lib/search";
import md from "../../../../CHANGELOG.md?raw";

export const prerender = true;
export const GET = () => json(buildIndex(FEATURES, GROUPS, [...FAQ, ...FIXES], parseChangelog(md)));
