# IntPortal

An unofficial student portal for PUP's SIS, for phones first. It signs in to the SIS on the student's behalf, keeps their schedule and grades on the device, and adds study tools around them.

## Language

### The SIS side

**SIS**:
PUP's Student Information System website, the one source of schedule and grade data.
_Avoid_: portal (when you mean the website), the site

**Host**:
One SIS server, such as `sis8.pup.edu.ph`. Hosts are not interchangeable. A good host signs in and serves schedule rows.
_Avoid_: mirror, site, domain

**Campus**:
The PUP campus a student belongs to, named by the two-letter code in their student number. It changes labels and identity, never the host.
_Avoid_: branch, school

**Term**:
One school year and semester pair, such as "2025-2026 First Semester". Grades and schedules belong to a term.
_Avoid_: semester (alone), period

**Sync**:
One trip to the SIS that refreshes the schedule and grades on the device.
_Avoid_: refresh, fetch, scrape (in user-facing text)

### The student's own layer

**Mark**:
The student's label on one class meeting: in person, online or vacant. It applies to one week, or to every week of the term. The SIS never knows about it.
_Avoid_: status, tag

**Subject color**:
The color the student gives a subject code. It survives every sync.
_Avoid_: class color, label

### The app's worlds

**Void**:
The dark space the app opens into before sign-in, where the portal forms.
_Avoid_: splash, launch screen

**Portal**:
One PUP system the app connects to, and the gate the student steps through to reach it. SIS is the first; Mabini is next. Each has its own login, limits and theme. Its frame is built from flat tiles (planned; pentomino pieces until then).
_Avoid_: door, gateway; never use it for the SIS website

**Opens soon**:
The status of a portal that is listed but not built yet. It shows its name and "Opens soon" and cannot be stepped into.
_Avoid_: coming soon, locked, disabled

**Theme**:
A portal's own colours: a five-tone ramp and one accent. It colours that portal's tiles and swirl. Not to be confused with a Room, which restyles the app.
_Avoid_: skin, palette (for the app's Rooms use Room)

**Hub**:
The landing once the student is signed in: the lit portal, LAR, and Step through.
_Avoid_: home, launcher

**Isko**:
The pixel student who stands for the student using the app. Isko never talks; Isko waves, cheers and keeps the streak.
_Avoid_: mascot, avatar, user (in copy)

**LAR**:
The Lakbay-Aral Robot, a small robot from the other side of the portal who came to study with Isko. LAR is the app's voice: the coach line, tips, empty states and errors.
_Avoid_: bot, assistant, Isko 3.0

**IskoLAR**:
Isko and LAR together, as a team. The name echoes "Iskolar ng Bayan".
_Avoid_: Isko and friend, the mascots

**Campus scene**:
The living pixel scene of PUP Sta. Mesa behind the hub. Its sky follows the real time of day, and the next class is a lit window.
_Avoid_: background, wallpaper

**Warp**:
The dive through a portal, from the hub into the Registrar.
_Avoid_: transition, loading

**Registrar**:
The in-app world after the warp, drawn in the SIS's own grammar: maroon menu, sheets, stamps.
_Avoid_: dashboard, main app

**Island**:
The pixel bar floating at the top of the Registrar. At rest it shows the glance. Opened, it holds the current screen's controls.
_Avoid_: toolbar, notch, Dynamic Island (that is Apple's)

**Glance**:
The island's one-line answer to "what now": the class in session, the next class, sync trouble, IntAssis thinking, or tomorrow's first class.
_Avoid_: status, ticker

**Room**:
One of the app's 15 looks. A room restyles the whole app, not only accents.
_Avoid_: theme, skin, palette

**Moment**:
A small piece of pixel theatre tied to a real event: the sync journey, a grade stamp, an empty-state scene.
_Avoid_: animation, easter egg

**Floating deck**:
IntAssis's chrome: the orb, its rail, the note formatting toolbar and the chat.
_Avoid_: dock; "orb" names only one part of it

### Study

**IntAssis**:
The app's AI assistant, running on a model on the device by default.
_Avoid_: AI, bot, chat

**Model download**:
The opt-in file IntAssis needs before it can answer. It shows its size, lives in the app's data folder outside backups, and the student can delete it from the Storage view.
_Avoid_: install, update

**Guide syllabus**:
A plan IntAssis generated from a course title, not read from the student's own syllabus. It is labelled "Guide".
_Avoid_: official syllabus, generated syllabus

**Deck**:
A set of flashcards on one topic, scheduled by FSRS.
_Avoid_: quiz (a quiz is a mode of reviewing a deck)

**Due**:
A card whose FSRS review date has arrived.
_Avoid_: pending, overdue (unless past due)

**Mastery**:
A card counts as mastered after at least two reviews, a stability of seven days or more, and a last rating other than Again.
_Avoid_: progress, completion
