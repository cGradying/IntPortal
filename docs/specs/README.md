# Specs

Every change in the UI revision starts here as a spec. Code follows an approved spec, never the
other way round.

## Flow

1. **Spec.** One file per area, from the template below. Reviewed and merged as a docs-only PR.
2. **Plan.** `/pstack:poteto-mode`, multi-phase-plan playbook, over the approved specs. Output is
   `docs/specs/PLAN.md`, one section per PR, linted by `check-plan.mjs`. Stops for an explicit go.
3. **Issue.** Each PR section becomes a GitHub issue (`docs/agents/issue-tracker.md`).
4. **Build.** One slice per PR. The old view is replaced in place and deleted in the same PR.
5. **Verify.** Tick the spec's acceptance boxes, each with the evidence it names.

## Direction

- **"The Portal and the Registrar"** (approved 2026-09-23): you land in a void, a pixel portal
  forms, you warp into the PUP SIS world drawn in the SIS portal's own grammar, pixel-forward. The
  app never embeds or shows the SIS web UI.
- **Reference build:** [`prototypes/intportal-v2.html`](prototypes/intportal-v2.html) (open it in a
  browser; press Return to skip the landing). `prototypes/registrar.html` is v1, kept for history.
- Behaviour: the current app is the reference. What works today keeps working unless a spec
  says otherwise under **UX changes**. Each spec's "Current behaviour inventory" is the parity list.
- Scope: macOS. Specs stay platform-neutral where they can so the WinUI port can reuse them.
- [`DESIGN.md`](../../DESIGN.md) is the foundation: tokens, type, shapes, motion, rules.

## Reference screenshots

- `reference/` holds committed, redacted crops (no student number, name, grades).
- `reference/private/` is gitignored and holds raw SIS captures.

## Index

Build in this order. Each row is one or more PRs; each spec lists its acceptance boxes.

| # | Spec | Area | Depends on | Status |
|---|---|---|---|---|
| 0 | Metal toolchain | `xcodebuild -downloadComponent MetalToolchain`, `swift build` green | — | done 2026-09-23 |
| 1 | [00-sis-host](00-sis-host.md) | SIS host failover (Core fix) | 0 | draft |
| 2 | [`DESIGN.md`](../../DESIGN.md) + [01-shell-navigation](01-shell-navigation.md) | Tokens, fonts, Pixel components, sidebar shell, shortcuts | 0 | approved |
| 3 | [09-landing-portal](09-landing-portal.md) | Launch void, portal, sign-in, hub, warp (Metal) | 2 | approved |
| 4 | [10-campus](10-campus.md) | Campus from student number | 3 | approved |
| 5 | [03-schedule](03-schedule.md) | Week grid, COR view, stamps, inspector | 2, backend W4/W5 | approved |
| 6 | [04-today-notebook](04-today-notebook.md) | Today screen, vault, editor, toolbar | 2 | approved |
| 7 | [05-grades](05-grades.md) | GPA, trend, table | 2, backend W1d | approved |
| 8 | [11-study-upgrades](11-study-upgrades.md) | Quizzes, study map, modes, recap, syllabus | 2, 6, backend W6 | approved |
| 9 | [06-assistant](06-assistant.md) | IntAssis + Ask AI restyle, split | 2, backend W9/W10 | approved |
| 10 | [07-settings](07-settings.md) | Settings screen, panes | 2, 4, 1 | approved |
| 11 | [08-menu-bar](08-menu-bar.md) | Menu bar panel | 2 | approved |
| 12 | HyperFrames trailer | 30 to 45s MP4 of void, portal, warp and app, rendered from prototype v3 for the README, releases and intportal-web. Never bundled in the app | 3 | planned |

Execution plan: [`PLAN.md`](PLAN.md) (phase 1: prototype v3, tokens, pixel components, depth kit, shell, landing; built by the head, landed by the operator). Phase 2 (screen slices, sonnet workers) goes in `PLAN-2.md`.
Prototype v3 (`prototypes/intportal-v3.html`) adds the 3D moves in DESIGN.md Signature components; it becomes the reference build once P3 lands.

Sign-in (former 02-login) is part of 09. Backend fix briefs: `.claude/plans/backend-fixes.md`
(local). Any agent guidance that still prescribes Liquid Glass for content (e.g. a `liquid-glass`
skill copied from PUPSISPortal) is retired by `DESIGN.md`. `PRODUCT.md` still names Ollama; refresh
it to llama.cpp/MLX + optional cloud providers when step 9 lands.

## Template

```markdown
# NN — Area

## Reference
SIS screenshot(s) and current-app screenshot(s), from `reference/`.

## Current behaviour inventory
Parity checklist pulled from the code. One line per behaviour, with its source file.

## UX changes
What moves, merges, or goes away, and why.

## Layout & components
Structure, components used from DESIGN.md, sizes.

## States
Empty, loading, error, offline, signed out, stale cache.

## Accessibility & motion
VoiceOver labels, keyboard paths, Reduce Motion behaviour.

## Acceptance criteria
- [ ] Criterion. Evidence: screenshot / test name / manual step.

## Seams
Core APIs the views call. Core changes are out of scope unless listed here.

## Out of scope
```
