# Team

IntPortal is built by several Claude sessions working in parallel, each with one role, and the user. This file says who owns what, how work moves, and how to start a role session.

## Roles

| Role | Owns | Simulator |
|---|---|---|
| Head (app lead) | the whole app: architecture, priorities, review and merge; `docs/`, `.github/`, `plugins/*/ios/`, `src-tauri/gen/apple/` | iPhone 17 Pro Max `C3E44428-02AC-4D0E-B3D2-8F69FEE2D703` |
| Core | `crates/intportal-core/`, `src-tauri/src/` | none; `cargo test` is the check |
| UI | `src/` | iPhone 18 Pro `F96E4771-D1B0-42DD-8F45-3DC691192F62` |
| QA/Release | tests across layers, `scripts/`, `CHANGELOG.md`, phone checks with the user | iPhone 17e `4A119F41-BF95-4D7A-A43C-744193BD853E` |
| AI | `crates/intportal-ai/`, `crates/intportal-llm/`, `spikes/s1-llama/`, `src-tauri/src/ai.rs`, `src/lib/assis/`, `docs/ai.md` | iPhone 17 `CFAAFAE1-9C75-47E3-9B38-143A150156B8`, CPU only; the Android emulator |
| Android | `src-tauri/gen/android/`, `plugins/*/android/`, Android-only code paths, `scripts/emu.sh` | the emulator |

The AI role's edits outside its paths go through issues only: the chunks table and `Plan.guide` (Core reviews), the hooks in `NoteEditor`, `DeckPage` and `SubjectPage` (UI), and `project.yml` (Head). Metal is checked on the user's iPhone through `scripts/phone.sh`, which the user runs.

A role edits outside its paths only when its issue says so. If a change needs another role's code, open an issue for that role, or ask the Head in the PR.

The user owns the SIS login and the phone. No session types, stores or asks for the SIS password or Apple ID. The user runs live SIS checks and phone installs.

## How work moves

0. **Spec.** No UI work without an approved spec in `docs/specs/`. See `docs/specs/README.md`. A change that contradicts a spec changes the spec first.
1. **Issue.** Every change starts as a GitHub issue with one `role:*`, one `type:*` and one priority (`P0` first, then `P1`; `P2` is later). `blocked` means waiting on something outside the repo. The Head files and triages them.
2. **Worktree.** `scripts/worktree.sh <role> <branch>` makes a worktree next to the repo from `origin/main`, installs packages, builds the CodeGraph index and prints the role's simulator. Branch names are `<role>/<topic>`; never `head/...`, which collides with `origin/HEAD` on macOS.
3. **Test first,** where a cheap test exists. See it fail for the right reason.
4. **Change,** then the checks in `CLAUDE.md`, and simulator or emulator screenshots for anything the student sees.
5. **PR** with `Closes #n` and, for spec work, a `Criteria:` line (`010 C1–C4`), from the template. Screenshots go in the PR, not in git.
6. **Review.** The Head reviews against the checklist below and leaves a comment that starts `Head review:` and says which criteria hold. Every session pushes as the same GitHub account, so GitHub can't record an approval; that comment is the approval.
7. **Merge.** Only the Head or the user merges. Engineers never merge their own PRs.
8. **Clean up.** After the merge, the owner removes its worktree and branch: `git worktree remove <dir>` and `git branch -d <branch>`.

## Working in parallel

Two or more engineers run at once. These rules keep them out of each other's way.

- **Handoffs live on GitHub, not in session messages.** A message between sessions is dropped when the sessions run in different permission modes. To hand work to another role, open an issue labelled `handoff` and `role:<theirs>` whose body has three parts: `ASK`, `CONTEXT` and `DONE WHEN`. Every session starts with `gh issue list --label handoff --label role:<mine>`. A live message is only a nudge to look.
- **Stay in your paths.** A change in another role's paths goes through a `handoff` issue to that role, or is named in your own issue and called out in the PR for the Head. No exceptions for "small" edits.
- **Hot files take turns.** `src-tauri/src/lib.rs`, `crates/intportal-core/src/store.rs`, `src/lib/state.svelte.ts`, `src/lib/api.ts`, `src/routes/+page.svelte`, the lockfiles and the version files are shared by every role. Keep changes to them small. If another open PR already touches the same hot file, say so in your PR; the Head merges the older one first and you rebase.
- **Merge one at a time.** The Head merges one PR, waits for the run on `main` to go green, then merges the next. A burst of merges hides which one broke `main`.
- **Short stacks.** At most two PRs deep, merged within a day. Rebase onto `main`; don't merge `main` into a branch. Stacked PRs merge bottom-up. Before deleting a merged base branch, point the next PR at `main` with `gh pr edit <n> --base main`.
- **One release at a time.** Versions are cut by QA/Release (the Head while no QA session runs) in a `release/x.y.z` PR that changes only the version files and `CHANGELOG.md`, and only when no other PR is waiting to merge.
- **Specs before builds.** A spec is approved on `main` before its first build PR opens. A build PR never carries the spec it builds.
- **Close the loop.** When a PR merges, its issue closes (`Closes #n`). Issues finished by work that didn't cite them are closed by hand with the PR number.

## Builds

All worktrees share one Cargo build cache in `~/.cargo/build/intportal` (`.cargo/config.toml`). Each worktree keeps its own `target/` for the final app. Two builds at the same time wait for each other. `scripts/disk.sh` shows the sizes; `scripts/clean.sh` deletes them.

## Review checklist

- The change fits `docs/ARCHITECTURE.md`: logic in the core, platform code in the shell or a plugin, the UI drawing what the core returns.
- Tests call the code the way its users do and assert literal results. A test that passes when the function returns nothing gets rewritten.
- The invariants in `docs/ARCHITECTURE.md` hold: data on the phone, own account only, the login in the keychain, the store encrypted, Reduce Motion honoured.
- Specs: the PR cites the criterion ids it delivers and the Head checks each one; tests are named after them.
- Screens: screenshots on the role's simulator; copy follows `PRODUCT.md` and `DESIGN.md`.
- No build output, screenshots or secrets in the diff. Paths are staged by name.
- If the change moves a layer, a flow or an owner, `docs/ARCHITECTURE.md` changes in the same PR.

## Starting a role session

Open a new Claude Code session in the repo and paste the role's prompt.

**Core**

```
You are the Core engineer for IntPortal. You own crates/intportal-core and src-tauri/src.
Read CLAUDE.md, docs/ARCHITECTURE.md and docs/TEAM.md first.
First: gh issue list --label handoff --label role:<your role> (handoffs from other roles).
Then take the open issues labelled role:core in priority order (P0 first): gh issue list --label role:core.
For each: scripts/worktree.sh core core/<topic>, write the failing test first, make the change,
run the checks in CLAUDE.md, open a PR with "Closes #n". The Head reviews and merges.
Never type, store or ask for the user's SIS password or Apple ID.
```

**UI**

```
You are the UI engineer for IntPortal. You own src/. Your simulator is iPhone 18 Pro F96E4771-D1B0-42DD-8F45-3DC691192F62.
Read CLAUDE.md, docs/ARCHITECTURE.md, docs/TEAM.md, PRODUCT.md and DESIGN.md first.
First: gh issue list --label handoff --label role:<your role> (handoffs from other roles).
Then take the open issues labelled role:ui in priority order (P0 first): gh issue list --label role:ui.
For each: scripts/worktree.sh ui ui/<topic>, test pure logic with vitest first, make the change,
run the checks in CLAUDE.md, check with screenshots from scripts/sim.sh on your simulator,
and open a PR with "Closes #n" and the screenshots attached. The Head reviews and merges.
```

**QA/Release**

```
You are the QA and release engineer for IntPortal. You own tests across layers, scripts/ and CHANGELOG.md.
Your simulator is iPhone 17e 4A119F41-BF95-4D7A-A43C-744193BD853E.
Read CLAUDE.md, docs/ARCHITECTURE.md and docs/TEAM.md first.
First: gh issue list --label handoff --label role:<your role> (handoffs from other roles).
Then take the open issues labelled role:qa in priority order (P0 first): gh issue list --label role:qa.
For each: scripts/worktree.sh qa qa/<topic>, make the change, run the checks in CLAUDE.md,
open a PR with "Closes #n". The Head reviews and merges. Phone installs are the user's to run.
```

**Android**

```
You are the Android engineer for IntPortal. You own src-tauri/gen/android, plugins/*/android and scripts/emu.sh.
Read CLAUDE.md, docs/ARCHITECTURE.md, docs/TEAM.md and docs/android.md first.
First: gh issue list --label handoff --label role:<your role> (handoffs from other roles).
Then take the open issues labelled role:android in priority order (P0 first): gh issue list --label role:android.
Follow shared-code changes from the Core and UI issues and check them on the emulator.
For each: scripts/worktree.sh android android/<topic>, make the change, run the checks,
open a PR with "Closes #n" and emulator screenshots. The Head reviews and merges.
```

**AI**

```
You are the AI engineer for IntPortal. You own crates/intportal-ai, crates/intportal-llm, spikes/s1-llama,
src-tauri/src/ai.rs and src/lib/assis. Your simulator is iPhone 17 CFAAFAE1-9C75-47E3-9B38-143A150156B8 (CPU only).
Read CLAUDE.md, docs/ARCHITECTURE.md, docs/TEAM.md and docs/adr/0003-on-device-ai-llama-cpp.md first.
First: gh issue list --label handoff --label role:<your role> (handoffs from other roles).
Then take the open issues labelled role:ai in order (A0 and A1 in parallel): gh issue list --label role:ai.
For each: scripts/worktree.sh ai ai/<topic>, write the failing test first, make the change, run the checks,
open a PR with "Closes #n". Nothing before A5 touches src-tauri/src/lib.rs. Linux CI never compiles llama.cpp.
The Head reviews and merges. Phone installs and Metal checks are the user's to run.
```

## Sprint 1: harden the base

Before new features. The issues:

| | Issue | Role |
|---|---|---|
| P0 | #60 Split `src-tauri/src/lib.rs` into modules | Core |
| P0 | #61 Typed IPC, generated TypeScript bindings (after #60) | Core |
| P1 | #62 Typed command errors (after #61) | Core |
| P1 | #63 SIS parser fixtures from real pages | Core |
| P0 | #64 Split Today, Grades and You into sections | UI |
| P0 | #65 Move to generated bindings and typed errors (after #61, #62) | UI |
| P1 | #66 Accessibility pass | UI |
| P0 | #67 Test strategy and coverage in CI | QA |
| P1 | #68 Smoke script that screenshots every tab | QA |
| P1 | #69 Versioning, CHANGELOG and a phone release checklist | QA |

Waiting on a paid Apple account: #24 (the widget's next class) and #26 (TestFlight).
