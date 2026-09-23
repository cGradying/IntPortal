# IntPortal

An unofficial native student portal for PUP's SIS. It signs in to the SIS on the student's behalf, keeps their schedule and grades, and adds study tools around them.

## Language

### The SIS side

**SIS**:
PUP's Student Information System website, the one source of schedule and grade data.
_Avoid_: portal (when you mean the website), the site

**Host**:
One SIS server, such as `sis8.pup.edu.ph`. Hosts are not interchangeable; a good host signs in and serves schedule rows.
_Avoid_: mirror, site, domain

**Campus**:
The PUP campus a student belongs to, named by the two-letter code in their student number. It changes labels and identity, never the host.
_Avoid_: branch, school

### The app's worlds

**Void**:
The dark space the app opens into before sign-in, where the portal forms.
_Avoid_: splash, launch screen

**Portal**:
The obsidian gate with the swirl that the student steps through to reach a system.
_Avoid_: door, gateway; never use it for the SIS website

**Hub**:
The ring of portals the student chooses from. Today only PUP SIS is live; the rest are locked.
_Avoid_: home, launcher

**Warp**:
The dive through a portal, from the hub into the Registrar.
_Avoid_: transition, loading

**Registrar**:
The in-app world after the warp, drawn in the SIS's own grammar: maroon menu, sheets, stamps.
_Avoid_: dashboard, main app

### Study

**IntAssis**:
The app's AI assistant, running on a local model by default.
_Avoid_: AI, bot, chat

**Deck**:
A set of flashcards on one topic, scheduled by FSRS.
_Avoid_: quiz (a quiz is a mode of reviewing a deck)

**Due**:
A card whose FSRS review date has arrived.
_Avoid_: pending, overdue (unless past due)

**Mastery**:
A card counts as mastered after at least two reviews, stability of seven days or more, and a last rating other than Again.
_Avoid_: progress, completion
