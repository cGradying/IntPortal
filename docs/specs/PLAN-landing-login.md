# IntPortal: new landing and login, multi-portal, and lockout safety, spec first

## Context

The user wants every UI change to start as a spec, beginning with the landing and the login. Over nine grilling rounds and eight live sketches (v1–v8, shown in chat) we settled the direction.

Today's landing works like this:
- three.js draws a 3D obsidian portal assembled from pentominoes;
- LAR comes through it;
- the sign-in card is docked below;
- the files are `src/lib/Landing.svelte`, `PortalStage.svelte`, `portal3d.ts`, `landing.ts`, `pentomino.ts` and `lar/`.

Two more needs came out of the grilling:
- **Lockout.** A student was locked out of their SIS account by too many login requests. The current code can cause that.
- **More than one portal.** The app will connect to more than one PUP system. Mabini, PUP's learning system, comes next. "SIS everywhere" has to give way to a portal model now, before it becomes a problem.

## Locked direction

**Look.** It follows the user's references:
- a butterfly next to its dot-matrix twin;
- earbuds drawn as cross-stitch;
- a still from Nothing's Playground film.

The result is a minimal, low-resolution grid of flat square **tiles** with gaps, on a black void, with four flat obsidian tones. There is no texture, no grain, no glyphs, no floor and no shaders. The portal faces the viewer head-on.

**Frame.**
- 24 blocks: 6 wide by 8 tall, one block thick, like a Nether portal. In tetromino terms that's I, L and J pieces.
- Each block is 2 × 2 tiles, giving a 12 × 16 tile grid: 11 px tiles on a 14 px pitch at 1×.
- The inner edge is one tone darker.

**Spawn.**
- The frame builds both ways at once, from the bottom centre up both sides, meeting at the top.
- Each tile pops in place over three stepped frames: a small light core, then the theme accent, then its tone.
- About 0.6 s in total, stepped at 30 fps.
- One haptic tick when the two sides meet.

**Tiles that react to the stage (sketch v8).**
- **At rest:** a few tiles quietly flip tone with a short shrink.
- **Connecting:** a soft accent pulse travels around the frame.
- **Opening:** an accent wave runs up both sides from the bottom centre and settles into a faint theme tint.

**Interior as state, drawn in the same tiles.**
- **Warp stars:** connecting (signing in, loading).
- **Swirl:** open.
- A dither dissolve of about 0.7 s turns one into the other.
- Colours come from the portal's school theme. SIS is PUP maroon and gold. Mabini is a placeholder until the user sends its colours.

**Portals.**
- A carousel. The selected portal is in the centre; the next one is dimmed beside it, with page dots under them.
- A portal that isn't ready shows "Opens soon" and can't be stepped into.
- It supports N portals from the start.

**Layout.**
- The portal fills the screen during the intro.
- It then lifts and shrinks to the top third as the form rises.
- It holds still while a field has focus.

**LAR.** He comes through the built portal, says one line, and stays as the voice above the form, smaller and quicker than today.

**Sign-in morph.**
- The portal's tiles flow into Today: the frame's tiles become the "Up next" card's frame and the tab icons, and the interior's tiles become the dot grid.
- The "fourth dimension" abstract animation plays during this transition. It gets designed in the prototype step.
- About 30% slower than a plain transition, because it's the hero moment.

**Login form.**
- Custom wheels for the birthdate (month, day, year) with stepped snapping, a haptic tick per step and a plausible year range.
- A masked student-number field.
- A show-password toggle.
- A visible "N tries left" line.
- The SIS's own error message, and an "SIS is down" state.
- Typography: a new premium pair from OFL fonts. Geist for the interface and Pixelify Sans for the wordmark, as tried in the sketches. Licences are checked in the spec.

**Motion budget.**
- Intro, waves and morph run at 30–60 fps. At rest, 12–20 fps with stepped motion.
- Rendering stops when the app is backgrounded.
- Reduce Motion shows a still, open portal and skips the morph.

**Renderer.**
- Rust compiled to WebAssembly, drawing tiles into a canvas in software. three.js and `portal3d.ts` are removed.
- The scene is a pure function of time and state, so `cargo test` checks frames, such as tile colours at a given t.

## Lockout safety (found in the code)

- `sign_in_with_failover` (`crates/intportal-core/src/sis/client.rs:141`) stops when SIS rejects the password. Good.
- It moves on to the next host after a successful sign-in with no schedule (`SignedInEmpty`), and after a network failure that may happen after the credentials were sent. PR #73 raises the host list from 3 to 8, so one tap could sign in up to 8 times.
- `sync` signs in again from the vault every time the session expires, with no cooldown.

The rules:
1. One credential POST per tap.
2. A plain GET picks a live host before any credential is sent.
3. Failover to another host only on connection errors that happen before the POST.
4. A `SignedInEmpty` result is reused rather than signing in on other hosts. Any further host check uses the open session, never a new sign-in.
5. After a rejected password, no automatic retry anywhere (sync, launch, ticker) until the student edits the login.
6. At most 3 attempts per 15 minutes per portal, counted on the phone and persisted. The form shows "N tries left".

**#73 stays on hold** until the guard lands, and is then rebased onto it.

## Phase 1: the spec PR (this Head session, docs only)

1. **`docs/specs/README.md`, the spec flow.** Spec, then the user approves it, then issues cite criterion ids, then tests are named after the criteria, then the Head reviews criterion by criterion. Statuses: draft, approved, building, shipped. Plus an index. Also `TEMPLATE.md`, with these sections:
   - status;
   - what changes for the student;
   - direction and references;
   - keep;
   - behaviour (numbered criteria);
   - copy;
   - data shape;
   - errors;
   - motion and Reduce Motion;
   - accessibility;
   - out of scope;
   - test map;
   - open questions.
2. **`docs/specs/reference/`.**
   - A README on how to capture and redact (no name, student number, birthdate, grades or photo).
   - `inspo/` holds the three art references, saved with their sources.
   - `prototypes/portal-v8.html` is sketch v8, saved as the visual reference.
   - `.gitignore` gets `docs/specs/reference/private/` for the user's raw SIS and Mabini captures.
3. **`000-sis-data-map.md`.**
   - Each SIS page the app reads (`client.rs`, `scrape.rs`): the login form at `/student/`, the schedule, `/student/grades` and the term picker.
   - The fields each gives, the `Snapshot` field they land in (`store.rs`), and the screens that show them.
   - Hosts (`host.rs`).
   - A "not read yet" list, filled from the user's captures.
4. **`010-landing.md`.** The locked direction above as numbered criteria: frame, spawn, tile waves, interior states, carousel, layout, LAR, morph, motion budget, Reduce Motion, and renderer boundaries.
5. **`011-login.md`.** The form, the copy, the error states and the lockout rules, plus the "keep" list from today:
   - student number, birthdate and password;
   - the demo link;
   - Step through for returning students;
   - the keychain note.
6. **`012-portals.md`, the portal model.**
   - A `Portal` in the core has an id, a name, a status (ready or opens soon), a theme (palette and accent), sign-in fields, attempt limits and a keychain service.
   - SIS is the only ready portal. Mabini is listed as opens soon.
   - Each portal has its own connection state and store namespace, so a second portal never touches SIS data.
7. **ADRs.**
   - **0003, "The landing renders in Rust/WASM tiles".** Retires three.js and pentominoes, keeps LAR.
   - **0004, "Portals are first-class".** The app connects to several PUP systems, each with its own login and limits.
   - Following the memory rule "ask before removing user-built UI": the old portal scene, the pentomino frame and the stones (Schedule, Grades, Study) are retired by the user's direction in this grilling. Confirm the stones explicitly in the spec PR.
8. **DESIGN.md.** Rewrite the landing register (tiles, tones, themes, motion), and add the font pair once the licences are verified. Update CONTEXT.md with the terms **Portal** (now one PUP system, not the website), **Opens soon** and **Theme**.
9. **TEAM.md.** Add step 0 to the loop ("Spec: no UI work without an approved spec") and a spec line in the review checklist.

## Phase 2: issues after the user approves the specs

| Issue | Role | Notes |
|---|---|---|
| Login guard: one POST, probe before credentials, no auto-retry after a reject, 3 per 15 min, "tries left" count exposed to the UI | Core, P0 | Test first in `sis/` with a fake client. Unblocks #73. |
| Portal registry (`portal.rs`), with SIS migrated onto it and Mabini as opens soon | Core, P1 | No behaviour change for SIS. |
| `crates/intportal-portal`: tile scene, timeline, waves, interior states, themes, carousel, compiled to WASM (wasm-bindgen), wired into `pnpm build` | Head | Frame tests in cargo. Size and fps measured on the 17e. |
| `PortalCanvas.svelte` host, layout lift, carousel UI, morph into Today; remove three.js, `portal3d.ts` and `pentomino.ts` | UI | After the renderer. Simulator screenshots of every state. |
| Login form: wheels, mask, toggle, tries-left line, error states, fonts | UI | After the guard (needs the count). |
| Prototype the 4D transition, then add it to 010 | Head | Sketch first, then the user approves. |

## Critical files

- **New:**
  - `docs/specs/{README,TEMPLATE,000-sis-data-map,010-landing,011-login,012-portals}.md`;
  - `docs/specs/reference/{README.md,inspo/,prototypes/portal-v8.html}`;
  - `docs/adr/0003-*.md` and `0004-*.md`.
- **Edited:** `.gitignore`, `DESIGN.md`, `CONTEXT.md`, `docs/TEAM.md`, `docs/ARCHITECTURE.md` (portal model and renderer layer).
- **Read, not changed, in Phase 1:**
  - `crates/intportal-core/src/sis/{client,host,scrape}.rs`, `store.rs`, `campus.rs`;
  - `src/lib/Landing.svelte`, `PortalStage.svelte`, `landing.ts`, `ErrorCard.svelte`, `state.svelte.ts` (`syncNow`);
  - `src-tauri/src/lib.rs` (`sync`, `sign_in`).

## Verification

- Every path, function and string the specs cite is found with `git grep`.
- `git check-ignore docs/specs/reference/private/x` confirms the private folder is ignored.
- `portal-v8.html` opens standalone and shows forming, connecting and open states and both themes.
- The font licences (OFL) are linked in DESIGN.md.
- CI is green on the docs PR.
- The user approves the specs before any Phase 2 issue is filed.
- Phase 2 then has its own checks:
  - guard tests (a single POST per tap, no retry after a reject, the 3-per-15-minutes limit);
  - cargo frame tests for the renderer;
  - simulator screenshots of every landing and login state on the 18 Pro and the 17e;
  - the WASM size and the fps on the 17e reported in the PR.

## Handoff notes (2026-10-11)

- Saved for the UI engineer to do later. Phase 1 (the spec PR) has not started; this branch holds only this plan, the v8 sketch and the gitignore line.
- Visual reference: `docs/specs/reference/prototypes/portal-v8.html` (open it in a browser).
- Art references are third-party images, so they stay out of git in `docs/specs/reference/private/` in this worktree (`../intportal-wt/docs-landing-login-specs`):
  - `ref-butterfly-dot-matrix.webp` (sent by the user);
  - `ref-stitch-earbuds.jpg` (Pinterest pin 1829656095125499);
  - `ref-nothing-playground-tiles.jpg` (Pinterest pin 2111131073843923, a still from Nothing's Playground launch film).
- Open items from the user:
  - Mabini's theme colours;
  - the SIS and Mabini captures for the data map;
  - the 4D transition, which needs a prototype first.
- PR #73 stays on hold until the login guard (Phase 2, Core P0) lands.
