// Stand-in for the app's store (src/lib/state.svelte.ts) when the site borrows
// the app's LAR: no student, no theme of their own, the SIS portal.
export const app = { mabiniConnected: false, sisConnected: true };
export const activeTheme = (): { lar?: number } | null => null;
