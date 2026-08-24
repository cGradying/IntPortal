  # README media — capture checklist

Not committed yet. Drop these files here, matching the names the main
`README.md` already references.

## Before every shot

- **No personal data on screen** — no student number, full name, grades, or
  faculty names unless you're fine publishing them.
- Grades shot: only if the numbers are ones you'd publish. Otherwise crop to
  just the GPA-trend chart, or skip it.
- Notes shot: use a note written for the screenshot, not a real one.
- Menu bar: clear out unrelated menu-bar items first.

## Shot list

| File | What | How |
|---|---|---|
| `hero.png` | Week grid, mid-week, now-line visible, 3–4 colored subjects, PUP Maroon theme | ⇧⌘4 then Space, window ~1440×900 first |
| `today.png` | Today screen, notes editor open, heading + checkbox + a bit of KaTeX | same |
| `assistant.png` | Assistant panel mid-answer with a source chip visible | ask it something over a demo note |
| `grades.png` | Grades screen or just the GPA trend chart | see privacy note above |
| `appearance.png` | Two themes side by side (PUP Maroon / Astra Moon) | two shots composited, or Settings → Appearance mid-switch |
| demo video | 20–40s: launch → week grid → drag-create event → mark class online → Today → assistant answers | ⇧⌘5 → Record Selected Portion, trim in QuickTime (⌘T), keep under 10MB |

`sips -Z 1600 docs/media/*.png` shrinks any retina PNG over ~2MB.

## Hosting the video

GitHub only gives a real inline player to files it hosts itself:

1. Open a new draft issue (or the release-notes editor) on the repo.
2. Drag the `.mp4`/`.mov` in — GitHub uploads it, inserts a
   `https://github.com/user-attachments/assets/…` URL.
3. Copy that URL, close the issue without submitting. The asset stays live.
4. Paste the bare URL on its own line in `README.md` where the `<!-- Demo
   video -->` comment is, near the top. GitHub auto-embeds it as a player.

Caveat: those URLs die if the repo goes private — the committed PNGs are the
fallback.
