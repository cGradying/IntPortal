import { FEATURES, GROUPS } from "$lib/content/features";

/** Spec 057 C9: the directory, every feature in its group. */
export const load = () => ({ groups: GROUPS, features: FEATURES });
