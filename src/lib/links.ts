/** The website's address once it is live (spec 051). Until then the Updates link opens GitHub's releases page. */
export const SITE: string | null = null;

const REPO = "https://github.com/cGradying/intportal-app";

/** Where You › Updates goes (050 C15). */
export const UPDATES = SITE ? `${SITE}/download` : `${REPO}/releases`;
export const PRIVACY = SITE ? `${SITE}/privacy` : `${REPO}/blob/main/PRIVACY.md`;
export const ISSUES = `${REPO}/issues`;
