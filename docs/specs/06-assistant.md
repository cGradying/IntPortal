# 06 — IntAssis (assistant) and Ask AI

Status: approved design (prototype v2). Visual redesign only; behaviour is parity.

## Reference
Prototype `intportal-v2.html`: `.orb-dock`, `.chat`, `CMDS`, `RAIL`, `reply()`, `actionRow()`,
`#helpPop`, `#thinkPop`; notes `openAsk()`; quizzes "Why?".

## Current behaviour inventory (parity checklist)
From `Views/AssistantFloating.swift`, `Core/Assistant/*`, `notes-editor/src/editor.js`:
- Orb bottom-left, tooltip "IntAssis"; hover rail with two page shortcuts that open chat and run a
  command (Schedule: "Next class" `/date <today>`, "This week" `/week`; Grades: "GPA trend" `/grades`,
  "Next class"; Notebook: "List notes" `/notes`, "Next class").
- Header: "IntAssis", ? "What can I ask it to do?" (popover "What it can do", grouped Calendar /
  Notes / Grades / Syllabus, tap fills the command; footer "Every change is shown to you first —
  nothing applies without a tap." or, in Auto, "Changes apply right away in Act automatically
  mode."), Thinking button ("Thinking: <level>" popover Off/Low/Medium/Max with explanations and the
  last raw reasoning or "No thinking yet — ask something."), mode label, Clear conversation, close,
  pin chip.
- Modes: "Propose only" / "Confirm each action" (default) / "Act automatically" (≤ 4 tool rounds,
  calendar adds undoable ⌘Z).
- Empty state text and "Runs locally and can be wrong. Check anything that matters."
- Input "Ask IntAssis… or /command"; `/` autocomplete (↑/↓, Tab/↵), argument hint after space.
- Slash commands: `/read /summary(/summarize) /create /rag /date /vacant /online /regular /week
  /grades /notes /find /event /move /think /help`; unknown → "Unknown command /x." + list.
- Tools: read_note, list_notes, search_notes, ask_notes, append_note, create_note, read_week,
  read_date, add_event, move_event, set_class_status, set_class_time, read_grades, read_syllabus,
  add_syllabus_item, set_syllabus_item_status. No delete/rename/grade changes.
- Replies reveal word by word (≤ 0.5s, ≤ 40ms/word); three blinking pixel squares while waiting;
  "thinking hard…" glitch at Max; errors with ⚠; RAG citation capsules "From your notes: …".
- Action rows ⚡ description + Skip / Apply.
- Notes: selection pill "Ask AI" → Summarize / Answer this / Structure this / Custom prompt… →
  "Thinking…" → preview → Replace / Insert below / Copy; reveal Sweep or Word blink (≤ 1.4s);
  "Turn on IntAssis in Settings first." when off.
- Quizzes: "Why?" 1–2 sentence explanation after a wrong answer.
- Cloud providers affect the chat only; everything else stays local.

## UX changes
1. **Visual:** orb = 48pt ink square with notch and a 24pt pixel sparkle (gold); hover rail = pixel
   chips; chat = sheet panel (410×540, notch, soft shadow) — no glass. Bubbles: you = action blue,
   IntAssis = sunk sheet. Citation capsules and the pin chip in gold-soft.
2. **Split `AssistantFloating.swift` (1,301 lines)** into `AssistantOrb`, `AssistantChatPanel`,
   `AssistantHelpPopover`, `AssistantThinkingPopover`, `ActionRow`. The **note formatting toolbar
   leaves the orb** and moves into the Notebook editor header (spec 04).
3. **Mode picker in the header** is a compact select showing the current mode.
4. **Copy fix:** Settings ▸ Intelligence footer must not claim the assistant can never move or
   change events (backend-fixes W10). Chat copy "Runs locally" switches to "Runs on {provider}"
   when a cloud provider is active (backend-fixes W9).
5. **Hover rail** per screen: Today and Schedule → Next class · This week; Grades → GPA trend · Next
   class; Notebook / Quizzes → List notes · Next class; Syllabus → This week · List notes; Settings →
   What can it do? · This week.

## States
AI off (Settings toggle): orb hidden, Ask AI pill shows the "Turn on IntAssis…" message.
Model not downloaded: chat input disabled with "Pick and download a model in Settings ▸
Intelligence." Busy: typing squares. Error: ⚠ line in `bad`.

## Accessibility & motion
Chat is a labelled region; messages `aria-live` polite equivalent (`accessibilityAnnouncement` for
new replies). Autocomplete is a listbox with arrow keys. Reduce Motion: no word reveal, no glitch,
typing squares static.

## 3D
While IntAssis waits on the model, its mark turns into `VoxelOrb` (token `think`), a spinning voxel cube: in the chat header while the chat is open, on the orb when it is closed. The message list keeps its pixel-square typing indicator.

## Acceptance criteria
- [ ] The orb is a voxel cube while a request runs and returns to the orb when it ends or fails. Evidence: screenshots.
- [ ] Every item in the parity checklist works. Evidence: manual pass, existing assistant tests.
- [ ] No behaviour change in `AssistantEngine` / tools. Evidence: diff limited to Views.
- [ ] `AssistantFloating.swift` removed; new files each < 400 lines.
- [ ] Copy fixes W9/W10 landed. Evidence: grep.

## Seams
`AssistantSession`, `AssistantEngine.respond/execute`, `RealAssistantExecutor`, `AssistantCommand`,
`Preferences` (mode, thinking, provider). Backend-fixes W9 (Task cancellation, partial results)
should land first.

## Out of scope
New tools or commands.
