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

## AI Assistant

### Floating assistant chat
**What it does** — A small orb in the bottom-left corner (reachable from every
screen) that expands into a chat panel. You ask it questions about your notes,
schedule, and grades, and it runs on Ollama — a local AI engine on your Mac,
so no data leaves your machine.

**How to use it** — **Settings → Misc → AI (beta)** — turn on "Floating
assistant". Make sure Ollama is running (`ollama serve` in a terminal), then
click the sparkles orb. The panel stays open across screens; type your message
and press Return. The assistant picks a permission level you set (see below) —
some replies just show you what it would do, others ask first, some act
automatically.

**Notes & limits** — Opt-in and off by default. Needs Ollama installed on your
Mac (download at ollama.ai); the app doesn't install it for you. Everything
stays local — no cloud, no API keys, no tracking. Your model stays running in
Ollama; switching models in Settings auto-unloads the old one if you want to save
RAM (manual "Unload other running models" button is there too).

**Getting a model** — **Settings → Misc → Download Models** lists the exact
terminal commands: install Ollama (`brew install ollama`), start it
(`ollama serve`), pull a chat model (`ollama pull qwen2.5-coder:1.5b` — small
and fast, what this app is built against), and pull the embedding model
(`ollama pull nomic-embed-text`) that note search runs on. A small model like
`qwen2.5-coder:1.5b` sometimes answers a notes question directly instead of
actually searching — `/rag "question"` always searches regardless of model
size. Grounded `/rag` answers additionally need `llama.cpp`
(`brew install llama.cpp`), which downloads its own model on first use.

### Permission levels
**What it does** — Three choices for how the assistant acts when it comes up with
something to do (add a calendar event, append text to a note, etc.):

- **Propose only** — shows what it would do, never acts.
- **Confirm each action** (default) — shows proposed actions and waits for you
  to tap "Apply" or "Skip".
- **Act automatically** — runs actions without asking.

**How to use it** — **Settings → Misc → AI (beta) → How the assistant
acts**.

### What the assistant can do
**What it does** — The assistant can:

- **Read your notes** — /read a note into the chat, or search notes by keyword
  to build context for its answer.
- **Read this week's schedule** — tomorrow, next class, what classes are in
  session, what's free time.
- **Read posted grades** — the grades you have and your current GPA.
- **Add calendar events** — create an event for any time/date you ask for.

The assistant never deletes, renames, or moves anything — no class block
changes, no grade edits, no existing event mutations. Every action it takes
goes through the same code path your own clicks would — undo, persistence,
and validation stay identical.

**How to use it** — Just ask naturally: "add a study session for Data
Structures on Thursday", "what am I doing tomorrow", "summarize my Discrete
Math notes".

**Notes & limits** — The assistant picks which tools to use on its own — you
don't type `/tool` unless you want to use slash commands (below). If it gets
stuck or picks the wrong tool, try rephrasing or use `/help` to see all
commands.

### Slash commands — deterministic tool picker
**What it does** — Type `/` into the chat and a filtered autocomplete palette
appears with keyboard navigation — five built-in commands that **always** run
exactly what you ask, no AI guessing:

- **`/read "Note Name"`** — pins a note into the conversation so the AI can
  reference it (no name = pins the note currently open on Today). The pinned
  note's full text feeds into your assistant's context.
- **`/summary "Note Name"`** — one-shot AI summary of a note, in a few sentences.
- **`/create a topic`** — writes a new study note from a prompt (e.g.,
  `/create photosynthesis regulation`), names it from your topic, and saves it.
- **`/rag "your question"`** — answers a question using only your notes vault
  (retrieval-augmented generation — see below). Guaranteed to actually search,
  unlike asking the assistant directly and hoping it decides to look.
- **`/help`** — lists all commands and their syntax.

**How to use it** — Type `/` to see the palette. Arrow keys (↑/↓) move the
highlight, Tab or Return selects it. While you're still typing the command word
(before the space), the full list filters; after the space, you get a one-line
hint of its argument. Command names can be abbreviated — `/r` completes to
`/read`, etc.

**Notes & limits** — Slash commands never use the AI — they're deterministic
and always do exactly what you type. `/read` without a name uses whatever note
is open on Today; if none is open or the named note doesn't exist, it tells
you. `/create` succeeds only if Ollama is running and you've set a model in
Settings.

### RAG — AI that actually searches your vault
**What it does** — When the assistant (or `/rag`) needs to answer using your
notes, it doesn't just keyword-match — it ranks notes by **meaning** using a
local embedding model (`nomic-embed-text`, pulled separately with `ollama pull
nomic-embed-text`). So a paraphrased question still finds the right note.
After finding matches, a second small local model (`llama.cpp`, LFM2-1.2B,
started automatically when needed) reads the matched text and writes one
grounded answer, citing which note(s) it drew from — shown as capsule chips
under the reply.

Falls back to plain keyword matching if the embedding model isn't installed, so
it still works either way — just less precisely.

**How to use it** — Just ask: "What does my Data Structures note say about
linked lists?" or use `/rag "question"` to guarantee the search runs. The
assistant will show which notes it read from.

**Notes & limits** — Embedding and answer models are optional and separate from
the main Ollama model. The app doesn't pull them for you. You can tune how the
search works — match strictness, how much context the answer model gets, how
creative vs. literal it is — in **Settings → Misc → AI Tuning**.

### Choose what the AI searches
**What it does** — Control which notes and folders are part of your vault's AI
search. By default, everything is included.

**How to use it** — Right-click any note or folder → **Include in AI search**
to toggle it on/off. Excluding a folder excludes everything inside it too.
Click the sparkles button in the **Vault** section header to see a count ("N
of M notes in AI search") and toggle a small badge on each row so you can see
at a glance what's included.

**Notes & limits** — Only notes you've included can be found by the AI; the
rest are untouched and unseen by any search.

### Color labels on notes and folders
**What it does** — Organize your vault visually. Right-click a note or folder
and pick a color label, or None. Shows as a tint on the icon in the sidebar.

**How to use it** — Right-click any note or folder → **Label** → pick a color.
Six preset colors (from your current theme's palette) or no label; purely
organizational, no other effect.

**Notes & limits** — Labels are stored locally with your notes and don't sync.
They're just for visual organization — they don't affect search, export, or
any other feature.

### Export a note
**What it does** — Save any note in three formats: Markdown (plain text), plain
text (stripped of formatting), or PDF (properly typeset with headings, bullets,
checkboxes, bold/italic, and code blocks highlighted).

**How to use it** — Right-click any note → **Export** → pick a format. A save
dialog opens; choose where to put the file.

**Notes & limits** — PDF export respects your note's Markdown: headings render
in different sizes, bullets and numbered lists stack, checkboxes show as ☐/☑,
`**bold**` and `*italic*` and `` `code` `` render styled. Math (`$…$` /
`$$…$$`) exports as literal text (KaTeX is live-only in the editor, not in
exports).

### Text-selection AI popup in the editor
**What it does** — Select any text while editing a note, and a small popup
offers four AI actions: **Summarize**, **Answer this** (treat it as a
question), **Structure this** (reorganize into a clean technical reference —
headings, bullets, isolated code), or **Custom prompt** (you type what to do).
Three ways to apply the result: **Replace** the selection, **Insert** below
it, or just **Copy** to clipboard.

**How to use it** — Select text in a note, and the popup appears. Click an
action or type your own prompt. The popup follows your app's theme colors and
clamps itself to stay on screen.

**Notes & limits** — Needs Ollama running and a model set in Settings. If the
AI request times out or fails, you get a one-line error and the selection
stays put. The popup is text-selection–only — it doesn't appear if nothing is
selected.

### Reveal animation when AI writes into a note
**What it does** — When AI-generated text lands (replace or insert below), it
fades in with a soft glow effect instead of appearing instantly, drawing your
eye to the change. Two animation styles:

- **Sweep** (default) — one continuous glow flowing down each line.
- **Word blink** — each word pulses independently.

Respects your Mac's Reduce Motion setting (collapses to a plain instant fade
if turned on).

**How to use it** — **Settings → Misc → AI (beta) → Text reveal** — pick
Sweep or Word blink. The choice applies the next time AI writes into a note.

**Notes & limits** — Pure eye candy — the glow is client-side only. Turn it off
in Reduce Motion if it distracts you.

### AI Tuning (advanced)
**What it does** — Fine-tune how RAG and grounded answers work. **Settings →
Misc → AI Tuning**:

- **Chunk size** — how much text gets grouped per search match (bigger =
  longer context, smaller = more precise). Default 700 chars.
- **Similarity floor** — how loose a match has to be to count as relevant
  (0.0 = anything goes, 1.0 = only perfect matches). Default 0.35.
- **Context budget** — how much matched text reaches the answer model (limits
  how many notes get read). Default 4000 chars.
- **Answer temperature** — how creative vs. literal the answer model is
  (0.0 = word-for-word, 1.0 = very creative). Default 0.2.
- **Embed model** — which embedding model to use (normally left alone). Default
  `nomic-embed-text`.

A **Reset to Defaults** button is there to undo changes all at once.

**How to use it** — Leave these alone unless you see issues — nobody needs to
touch this for the feature to work. If answers are too vague, lower temperature
or raise the similarity floor. If too many irrelevant notes are included,
lower chunk size or context budget.

**Notes & limits** — These are advanced knobs for the retrieval pipeline. The
defaults are tuned for a typical student vault (dozens to hundreds of notes).
Very large vaults (thousands of notes) might need tweaking.

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

---

## Settings

### Data & Storage
**What it does** — Shows the real, current disk usage of everything the app
stores — the schedule cache, notes vault, syllabus, quiz decks, and every
downloaded AI model — with a running total and a Reveal-in-Finder button per
item.

**How to use it** — **Settings → Storage**. Delete a downloaded model
straight from the list to free space; the model currently selected in
**Settings → Intelligence** can't be deleted until you switch off it first.

**Notes & limits** — Sizes are read once when the pane appears (and again
after a delete), not recomputed on every redraw — a large quiz-deck folder
doesn't cause a stall just from having the pane open.

### Advanced AI tuning
**What it does** — Four knobs the local assistant always had fixed values
for, now real controls: response **temperature** (focused vs. varied),
**output token budget** (the ceiling on one reply), **KV cache
quantization** (roughly halves the running model's RAM cost per token of
context), and **GPU (Metal) offload** — off forces CPU-only, useful for
isolating a slowdown or crash.

**How to use it** — **Settings → Intelligence → Advanced AI Tuning**, gated
behind IntAssis being on. **Reset to Defaults** restores all four at once.

**Notes & limits** — All four restart the local model process when changed.
On Apple Silicon the default model runs on MLX, which manages its own KV
cache and always uses the GPU — the quantization and GPU toggles only reach
the Intel-fallback `llama-server` model.

### Reset to Defaults
**What it does** — Every pane with its own settings (General, Appearance,
Schedule, Notifications, Intelligence) has a **Reset This Pane to Defaults**
button that puts just that pane's controls back to first-launch values.
General also has **Reset All Settings…**, a true factory reset of every
setting in the app.

**How to use it** — Bottom of each pane; the global reset asks for
confirmation first.

**Notes & limits** — Deliberately narrow: per-class colors, online/vacant
marks, moved times, class notes/links, and syllabus tasks are real data set
from the week grid and Appearance's subject rows, not a "setting" — none of
that is touched by either reset, nor is your schedule cache, notes, or quiz
decks.

### Force Reduce Motion
**What it does** — An in-app override, independent of System Settings' own
Reduce Motion, for this Settings window's own animations (deleting a
downloaded model, the RAM-estimate warning color).

**How to use it** — **Settings → General → Motion**.
