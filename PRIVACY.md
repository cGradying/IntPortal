# Privacy

IntPortal is an unofficial student app. It works with your school's own portals, which today are the SIS and eMabini of the Polytechnic University of the Philippines (PUP). It is not made by or affiliated with any school. This page says what the app does with your data. Last updated 2026-11-16.

## The short version

- Your login is kept on your phone and only ever sent to your school. Your data stays on your phone. There is no IntPortal account, no IntPortal server, no analytics and no ads.
- The app talks to your school's own systems with your own login, the way you would in a browser.
- Nothing is sold or shared, because nothing is collected.

## What stays on your phone

- **Your login** for the SIS and eMabini. It is kept in the phone's keychain (the iOS Keychain, or the Android Keystore).
- **What the app reads from your school**: your schedule, grades, courses and deadlines. It is saved in a database on the phone, encrypted with SQLCipher. The key is kept in the keychain, and each student who signs in on the phone gets their own file.
- **What you make**: notes, note photos, study decks, deadlines you add, goals, your name for LAR, your campus and your look.
- **Scans**: a photo you scan for text is read on the phone and not kept, unless you attach it to a note.
- **The optional AI** (IntAssis). It runs entirely on the phone, and your questions and notes never leave it.

## Who the app talks to

| Service | When | What is sent |
|---|---|---|
| PUP SIS (`sis8.pup.edu.ph` and its mirrors) | Signing in and syncing | Your student number, birthdate and password, sent to PUP only, to sign in as you |
| PUP eMabini (`emabini.pup.edu.ph`) | If you connect eMabini | Your eMabini login, sent to PUP only |
| Hugging Face (`huggingface.co`) | Only when you add LAR's AI ("With AI" at first run, or Add IntAssis in You), update it or switch models | Plain downloads of the AI model files; nothing about you beyond the download request itself |
| Google Play services (Android only) | The first time you scan, if the scanner isn't on the phone yet | Google's standard request to download the text and QR scanner; no photo is sent |
| Your browser | When you tap a class link (Meet, Zoom) or eMabini | Whatever that site normally gets when you open it |

The app sends nothing anywhere else. It has no crash reporting, analytics, tracking or advertising SDKs.

## Permissions

- **Notifications**: class and deadline reminders, scheduled on the phone.
- **Camera and photos**: only when you tap Scan or add a photo to a note.
- **Calendar**: only if you turn on calendar sync in You; it writes your classes and deadlines to a calendar on the phone.
- **Face ID or fingerprint**: only if you turn on the app lock.

## Deleting your data

- **Sign out** (You › Accounts) removes your login and your SIS data from the phone and keeps your notes and decks for when you sign back in.
- **Erase everything** (You › Privacy) removes everything IntPortal saved for you.
- Uninstalling the app removes everything too.

Backups are files you make and share yourself (You › Backup). A backup holds your notes, decks, deadlines and settings, never your logins, and only a salted hash of your student number. Keep it somewhere you trust, because it is not encrypted.

## Children

IntPortal is for students. It collects nothing, so it collects nothing from anyone under 18 either.

## Changes and contact

Changes to this page are listed in the repository's history. Questions or problems: open an issue at <https://github.com/cGradying/IntPortal/issues>.
