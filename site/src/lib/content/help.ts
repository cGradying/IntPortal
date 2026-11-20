// Spec 057 C11 and 058 C5: the help page's questions and fixes. Each id is its
// address on /help, so search and shared links can open it.
export type HelpItem = { id: string; q: string; a: string };

export const FAQ: HelpItem[] = [
  { id: "q-is-this-official", q: "Is this official?", a: "No. IntPortal is an independent student project. It isn't made by or affiliated with any school, and only works with your own account." },
  { id: "q-is-my-password-safe", q: "Is my password safe?", a: "It never leaves your phone except to sign in to your school's own portal. It's kept in the phone's keychain, and the app makes at most three sign-in tries every fifteen minutes so it can never lock your SIS account." },
  { id: "q-does-it-work-offline", q: "Does it work offline?", a: "Yes. After one sign-in, your schedule, grades, deadlines, notes and decks are on the phone. It syncs again when you have signal." },
  { id: "q-is-it-free", q: "Is it free?", a: "Yes: free to download and use, with no ads. The code is published on GitHub so anyone can read it; it isn't open for reuse, so copying or changing it needs permission." },
  { id: "q-why-isnt-it-on-the-app-store", q: "Why isn't it on the App Store?", a: "Publishing there needs a paid Apple developer account. Until then, iPhone users can sideload it with AltStore or SideStore, or try it in the browser." },
  { id: "q-what-about-other-schools", q: "What about other schools?", a: "More are coming. The portal wall already lists other schools' portals, and today PUP's SIS and eMabini sign in." },
  { id: "q-does-the-ai-send-my-notes-anywhere", q: "Does the AI send my notes anywhere?", a: "No. LAR's assistant runs on the phone itself, and you turn it on yourself. Your questions and notes stay on the phone." },
];

export const FIXES: HelpItem[] = [
  { id: "q-it-says-to-wait-before-signing-in-again", q: "It says to wait before signing in again", a: "After three tries in fifteen minutes the app stops and tells you when you can try again. It never retries a rejected password on its own, so it can't get your school account locked. If you forgot the password, Forgot password opens your portal's own reset page." },
  { id: "q-the-sis-isnt-answering", q: "The SIS isn't answering", a: "A chip under the portal says so; it checks without sending your login. Everything you already have still opens offline. Pull down on Today to sync again once the SIS is back." },
  { id: "q-reminders-dont-come", q: "Reminders don't come", a: "Turn them on in You, then check that your phone allows notifications for IntPortal in its Settings." },
  { id: "q-the-iphone-app-stopped-opening", q: "The iPhone app stopped opening", a: "Apps signed with a free Apple ID stop opening after 7 days. Open AltStore or SideStore and refresh IntPortal; your data stays." },
  { id: "q-the-mac-says-it-cant-open-intportal", q: "The Mac says it can't open IntPortal", a: "The Mac build isn't signed yet. The first time, open it from the right-click menu and choose Open." },
  { id: "q-windows-says-it-protected-your-pc", q: "Windows says it protected your PC", a: "That's SmartScreen, because the build isn't signed. Choose More info, then Run anyway." },
  { id: "q-moving-to-a-new-phone", q: "Moving to a new phone", a: "Make a backup in You and open it on the new phone, or just sign in again: your schedule and grades come back from the SIS. Your own notes and decks are only in the backup." },
];
