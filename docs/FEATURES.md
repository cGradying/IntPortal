# PUPSISPortal — Features

What the app does, in plain terms, kept current as features ship. This is the
source the README sections, a wiki, and release notes are assembled from.

Examples use fake data (`COMP 20073`, "Data Structures") — never a real
schedule.

---

## Your schedule

### Native weekly calendar
**What it does** — Signs into the PUP SIS in the background and draws your
enrolled classes as a proper weekly calendar. You never see the SIS website
itself; the app reads your schedule and renders it natively.

**How to use it** — Enter your student number, birthdate, and password once.
The week grid appears with every class in its day-and-time slot. Use the
arrows (or ⌘[ and ⌘]) to move between weeks, and **Today** to jump back.

**Notes & limits** — Only your own account, which is what PUP's terms allow.

### Opens instantly, even offline
**What it does** — Your schedule is saved on your Mac, so the calendar is on
screen the moment you open the app — no waiting for sign-in, no spinner. It
then refreshes quietly in the background.

**How to use it** — Nothing to do; it's automatic. The footer shows when the
schedule was last updated.

**Notes & limits** — If a background refresh fails (no internet, SIS down), the
app keeps showing your saved schedule and notes the problem in the footer
rather than replacing your week with an error. Signing out erases the saved
copy.

### Year view
**What it does** — Zooms out to a whole year at a glance.

**How to use it** — Switch **Week / Year** in the toolbar. Click any week to
jump straight to it.

### Now-line
**What it does** — A line across the grid marks the current time, with a small
live clock, so "where am I in the day" is a glance.

---

## What's next

### Next-class banner
**What it does** — The footer shows your next class and how long until it
starts — "COMP 20073 in 25 min", or "in session" while one is running. After
the last class of the week it looks ahead to next week's first.

**Notes & limits** — Classes you've marked vacant are skipped. Online classes
still count — you still have to show up.

### Menu bar
**What it does** — Puts your next class in the Mac menu bar, always visible.
Click it for a small panel: the countdown, the rest of today's classes,
whether reminders are on, and buttons to open the app, refresh, or quit.

**How to use it** — It's there whenever the app is running, even with the main
window closed — which is what keeps reminders firing while you work in other
apps.

---

## Reminders

### Notifications before class
**What it does** — Sends a notification a few minutes before each class starts,
repeating every week.

**How to use it** — **Settings → Notifications → Remind me before class**.
macOS asks permission the first time. Pick how early you're warned (5, 10, 15,
or 30 minutes).

**Notes & limits** — Reminders only fire while PUPSISPortal is open. Meetings
you've marked vacant are skipped. If you turn notifications off for the app in
System Settings, the toggle here offers a shortcut back to fix it.

---

## Calendar sync

### See your other calendars alongside class
**What it does** — Draws events from your chosen Calendar.app calendars in the
same grid as your classes, so personal commitments and class don't live in two
apps.

**How to use it** — **Settings → Calendar → Connect…**, then tick the calendars
you want shown.

### Add, move, and edit events
**What it does** — Create events by dragging on the grid — including across
several days at once — then move, resize, duplicate, or delete them. Everything
you do here is written straight into Calendar.app, so it syncs to your phone.

**How to use it** — Drag on an empty part of the grid to create; ⌘-drag to
select several; drag a block to move it, or its edge to resize. Right-click a
block for its menu. ⌘Z undoes.

**Notes & limits** — Editing a repeating event asks whether you mean just that
day or all future ones. Class blocks come from the SIS and can't be edited
here — they'd be overwritten on the next refresh.

### Export your classes to Calendar.app
**What it does** — Writes your whole class schedule into a calendar you pick,
as weekly repeats, so your classes show up on all your devices.

**How to use it** — **Settings → Calendar**, choose which calendar to add to
and a "repeat until" date (usually the end of term), then **Add to Calendar…**.

**Notes & limits** — Needs a calendar you can edit; the app won't create one.
Running it again replaces the classes it added before and leaves your own
events alone. Classes you've marked **online for the whole term** are labelled
"(Online)"; classes marked **vacant for the term** are left off entirely — so
your calendar matches what you set. Re-run the export after changing a status.
Exported classes are hidden from the app's own grid so they don't appear twice —
they're still in Calendar.app.

---

## Grades

### Your grades, with a real GPA
**What it does** — Shows each subject you're enrolled in with its final grade,
and computes your GPA — weighted by units, the way it actually counts — rather
than just reprinting what the SIS shows.

**How to use it** — Pick **Grades** in the sidebar. Each subject lists its
units and grade; the GPA sits at the top.

**Notes & limits** — Grade cells are blank until the school posts them, which
is the normal state for most of a semester — those subjects read "Pending" and
don't affect the GPA. Incomplete or dropped marks (INC, DRP) are listed but
left out of the average. Until anything is posted, the GPA shows a dash, not a
zero. Like the schedule, grades are saved on your Mac so the page opens
instantly, and are erased when you sign out.

---

## Appearance

### Themes
**What it does** — Two hand-tuned looks — **PUP Maroon** (maroon and gold on
warm paper) and **Astra Moon** (emerald on deep navy) — or **Match System** to
follow light/dark automatically.

**How to use it** — **Settings → Appearance → Theme**.

### Per-subject colors
**What it does** — Each subject gets its own color automatically, and you can
override any of them.

**How to use it** — **Settings → Subject Colors**, pick a color per subject
code. **Reset** returns one to its default.

**Notes & limits** — Colors are remembered per subject code and survive a
refresh.

### Mark a class online or vacant
**What it does** — Tag each meeting as in-person, online, or vacant — something
the SIS doesn't tell you. Online classes get a coloured strip around them, whose
colour you can set per subject. Vacant meetings are dimmed.

**How to use it** — Click a class block for its panel, or right-click it, and
pick a status. A status applies to **just the week you're viewing** by default;
tick **Every week this term** to make it stick across the semester. For online
classes the panel also has an "Online strip" colour.

A class marked vacant **disappears** from the week grid — a cancelled class
shouldn't take up space. Use **Show Cancelled** in the toolbar to bring hidden
ones back (faded) if you need to restore one.

**Notes & limits** — Status is per meeting, not per subject: the same course can
be in-person on Tuesday and online on Friday. Reminders, the next-class banner,
and the Apple Calendar export act on a **whole-term** status (the "every week"
tick): term-vacant classes are dropped from the export automatically and
term-online ones are relabelled — no manual re-export. A single vacant week only
hides that week in the app, since a repeating calendar event and a weekly
reminder can't skip one occurrence.
