# Product — IntPortal Web (draft)

Sibling product to the native `PUPSISPortal` Mac/Windows app. This document states the
commitments that differ from the native app's own `PRODUCT.md` — do not assume parity
by default; the two commitments below are the ones the native app makes that this
product explicitly cannot.

## What's different from the native app

1. **Credentials are not machine-local.** The native app's commitment is "Credentials
   live only in the Keychain" — true because it runs on one Mac the student owns.
   IntPortal Web is a hosted multi-user service: your SIS password (if you opt into
   "remember me") and your Anthropic API key are held, encrypted, on a server you don't
   control. See `THREAT-MODEL.md` and `PRIVACY.md` for exactly what that means and what
   it protects against. This is disclosed on the login screen, not buried.

2. **AI is not local-only.** The native app's commitment is "nothing leaves the
   machine" via a local model. IntPortal Web has no local model — AI features call
   Anthropic's API using a key you supply, and your prompt content leaves this service
   and goes to Anthropic. This is disclosed in `TERMS.md` §5 and `PRIVACY.md`.

Both of these are structural consequences of hosting a multi-user web service, not
oversights. State them plainly everywhere the native app's docs state their opposite,
rather than let this document contradict the native one.

## What stays the same

Everything else in the native app's `PRODUCT.md` — the audience (PUP students with
their own SIS8 account), the purpose (native/fast access to their own schedule, grades,
and study tools the official portal doesn't offer), the own-data-only scope, and the
design language — is the target for this port, not being renegotiated.

## Positioning note

Because this is a *hosted* service touching other students' PUP credentials, it carries
a materially different trust posture than a tool that runs entirely on someone's own
machine. `TERMS.md` states plainly that this is an unofficial, unaffiliated tool built
by a student — that framing should show up in the product's own copy (login screen,
about page), not just the legal documents.
