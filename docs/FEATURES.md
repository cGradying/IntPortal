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
Click it for a today-at-a-glance panel: today's date, the next class with its
countdown, the rest of today's classes (the one in session marked "now"), a
look-ahead to tomorrow's first class once the day's winding down, whether
reminders are on, and buttons to open the app, refresh, or quit.

**How to use it** — It's there whenever the app is running, even with the main
window closed — which is what keeps reminders firing while you work in other
apps. A class you've marked vacant this week drops from the list, same as on the
grid.

### Today view
**What it does** — A read-only daily rundown next to the week grid: today's
classes top to bottom, the one happening now highlighted "In session", finished
ones dimmed "Done", and upcoming ones with a countdown ("in 25 min" / "at 2PM").
Free stretches between classes show as "2h 15m free", and a line at the bottom
previews tomorrow's first class.

**How to use it** — Click **Today** in the sidebar. On a free day (weekend, term
break) it shows a clean empty state with the tomorrow line still there.

**Notes & limits** — Display only — nothing here edits the schedule. Classes
marked vacant for the week are dropped, matching the grid.

---

## Notes

### A live Markdown editor, right by your day
**What it does** — Attaches notes to the Today screen in a proper editor that
renders as you type (Obsidian-style live preview — no separate Edit/Preview
mode). Notes are saved on your Mac and open instantly.

**How to use it** — Click a class or event row to open its note, use the day
scratchpad for anything undated, or build a vault of folders and named notes in
the sidebar. Open notes stack as tabs above the editor. A toolbar drives the
formatting; you can also type the Markdown directly.

**Notes & limits** — A class note is **shared across every week** that class
meets — one note per subject, not one per week — so ongoing notes for a course
stay in one place.

### Dated log for a class
**What it does** — Turns a class note into a running, dated log so you can tell
when each bit was written.

**How to use it** — On a class note, click **Add dated entry**. It appends a
`## <date>` heading and offers two dates: the subject's **next class meeting**
(computed from your schedule — e.g. writing on the 15th for a class that next
meets the 16th stamps the 16th) or **today**.

### Rich content
**What it does** — The editor is more than plain text:

- **Formatting** — headings, bold, italic, strikethrough, highlight, colored
  text, quotes, and bullet / numbered lists.
- **Dividers** — a horizontal rule to break sections.
- **Task checkboxes** — `- [ ]` / `- [x]` become real checkboxes you click to
  tick off.
- **Math** — `$…$` and `$$…$$` render live via KaTeX.
- **Code blocks** — fenced ```` ```language ```` blocks get syntax highlighting,
  a language badge, and a copy button.
- **Note links** — `[[Title]]` is a clickable link that jumps to that note.
- **Images** — paste an image, drag one in, or use an image URL; it shows inline.
- **Tables / database** — an interactive table with typed columns: text,
  number, checkbox, date, and a **status** column with your own custom-colored
  tags (add your own labels and colors, not a fixed list). Click cells to edit,
  drag a column edge to resize it, and add or remove rows and columns — the `×`
  controls appear when you hover.

**How to use it** — Use the toolbar above the editor, or type the Markdown by
hand. Insert a table or divider from the toolbar; click a status cell to pick or
create a tag.

**Notes & limits** — Everything is stored as plain Markdown text in the note, so
it stays portable. Pasted/dropped images are copied into the app's storage
(Application Support), same privacy terms as the rest of your data.

---

## Reminders

### Notifications before class
**What it does** — Sends a notification a few minutes before each class starts,
repeating every week.

**How to use it** — **Settings → Notifications → Remind me before class**.
macOS asks permission the first time. Pick how early you're warned (5, 10, 15,
or 30 minutes).

**Notes & limits** — Reminders fire only while PUPSISPortal is running. Turn on
**Settings → Notifications → Start at login** so the app relaunches after a
restart and is always there to fire them. Meetings you've marked vacant are
skipped. If you turn notifications off for the app in System Settings, the
toggle here offers a shortcut back to fix it.

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

**How to use it** — **Settings → Calendar**, choose which calendar in-person
classes go to and a "repeat until" date (usually the end of term), then **Add to
Calendar…**. You can send **online classes to a separate calendar** ("Online
classes to") — a different colour/label in Apple or Google Calendar — or leave
them with the rest.

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

### GPA trend across terms
**What it does** — Beyond the current term, the Grades screen draws a **GPA
trend line** across every past term and shows **units completed** toward your
program's total — the two things SIS shows one term at a time but never puts
together. A term picker lets you flip the subject list back to any past
semester.

**How to use it** — Click **Load past terms** on the Grades screen; the app
steps through your School Year / Semester dropdowns and pulls each term. Set
your program's total required units in **Settings → Grades** to get a
completed-of-total progress bar (SIS doesn't publish that total).

**Notes & limits** — Only terms with posted grades appear on the trend. Better
GPAs sit higher on the line (PUP grades run 1.00 best to 5.00). Past terms are
saved on your Mac alongside the current one and erased on sign-out. A repeated
subject currently counts its units each time it appears.

---

## Appearance

### Themes
**What it does** — Three hand-tuned looks — **PUP Maroon** (maroon and gold on
warm paper), **Ivory** (ink navy on cream, an editorial light look), and
**Astra Moon** (emerald on deep navy) — or **Match System** to follow light/dark
automatically.

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

A class marked vacant stays visible in its slot, faded, so you can still see and
restore it. Use **Hide Cancelled** in the toolbar for a cleaner week once you're
done.

**Notes & limits** — Status is per meeting, not per subject: the same course can
be in-person on Tuesday and online on Friday. If you've exported to Apple/Google
Calendar, status changes sync there automatically: a class vacant **for the
term** is dropped entirely, a class vacant **just one week** keeps repeating but
loses that week's date, and an online class is relabelled "(Online)" — no manual
re-export. (The calendar only syncs once you've picked an export calendar in
Settings.) Reminders and the next-class banner still act on whole-term status
only — a weekly reminder can't skip a single week.
