# Threat model — IntPortal Web

Draft for the hosted multi-user port. Written before any code — it decides what the rest of the
build is allowed to do, not a retrofit.

This is an **unofficial student-built tool**, not affiliated with, endorsed by, or
operated by the Polytechnic University of the Philippines. It signs into a student's
own SIS8 account, as them, using credentials they supply, to read their own data only.

## Assets and controls

| Asset | Threat | Control |
|---|---|---|
| SIS password (other students') | Database dump / stolen backup | AES-GCM. Key derived from the user's **own SIS password** via Argon2id + a per-user random salt. Key is never stored server-side, never in env vars, never in logs — it exists only inside the encrypted session, for the life of that session. A database dump alone is undecryptable. |
| SIS password | Compromised server process during an active session | **Not defended.** A live request handler holds the derived key while decrypting. This is the residual risk of running the service at all; stated in the ToS rather than papered over with a claim we can't back. |
| SIS session cookies (from our client to sis8.pup.edu.ph) | Session theft, replay | Stored encrypted (same key), never sent to the browser. Our own session cookie to the user: httpOnly, Secure, SameSite=Lax, 30-day max, rotated on login, invalidated server-side on logout. |
| Anthropic API key (user-supplied) | Exfiltration via response body, logs, or the JS bundle | Encrypted at rest with the same derived key; decrypted only inside the proxy request; excluded from every response schema by construction (not by filtering) — a test asserts it never appears in a response body. |
| Scraped personal data (name, student number, grades) | Leakage into logs / error traces / crash reports | Structured logging with an explicit field allowlist, not a blocklist. No request/response body logging in production. Error responses carry no scraped content, ever — errors are coded, not echoed. |
| Notes, syllabus, decks (user-authored) | Cross-user access via a guessable ID or a missing filter | Every query goes through one shared `current_user()` dependency and is filtered by `user_id` from the session — never from a request parameter. No route queries by raw ID without that filter. Enforced by a test per resource type. |
| SIS itself (sis8.pup.edu.ph) | This service hammering it on behalf of many users | Per-user rate limit on `/api/refresh`, a global concurrency cap across all users, an honest identifying User-Agent, no polling faster than a human would click refresh. |
| Anthropic account (per user) | Runaway loop burning someone's tokens | Per-user rate limit on the AI proxy even though the user pays — it's still our bandwidth and their money if something loops. |

## What is *not* in scope

- Defending against a user attacking their own account — it's theirs.
- Defending against Anthropic's or Vercel's or Neon's own infrastructure being
  compromised — that risk is disclosed (named as processors in `PRIVACY.md`), not
  mitigated by us.
- Making the service available if SIS itself is down or changes its markup — that's
  Phase 1's fixture-based tests catching drift, not a security control.

## Non-negotiables checklist (Phase 2 acceptance criteria)

- [ ] Argon2id parameters chosen and recorded here once picked (time cost, memory cost,
      parallelism) — not left at library defaults without a decision.
- [ ] All secrets from environment only; `.env` gitignored; **no fallback default for
      any secret in code** (a missing key must fail startup, not silently use a weak one).
- [ ] CSRF protection on every state-changing route.
- [ ] Security headers: HSTS, CSP with no `unsafe-inline`, `X-Content-Type-Options: nosniff`,
      `Referrer-Policy: same-origin`.
- [ ] Postgres connection over TLS.
- [ ] `pip-audit` and `npm audit` run in CI, failing the build on high/critical.
- [ ] A working, tested account-deletion route that removes every row and blob for a
      user — not a soft-delete flag.
- [ ] Cross-user access denial is a test, not an assumption, for every resource type
      (`docs`, `decks`, `reviews`, `note_images`).
- [ ] A test asserts the Anthropic key and the SIS password never appear in any API
      response, including error bodies.

## Revisit triggers

Re-read this document (not just Phase 2, always) if: the encryption key derivation
changes, a new secret type is introduced, a route is added that queries by ID without
going through `current_user()`, or SIS's own auth flow changes.
