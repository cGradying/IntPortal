# Portals are first-class

The app connects to several PUP systems, not only the SIS. A **portal** is one such system, with its own login fields, attempt limits, host handling, theme, status (ready or opens soon), keychain entry and store namespace. SIS is the first ready portal; Mabini, PUP's learning system, is next and shows "Opens soon" until it is built.

"SIS everywhere" in the core and UI gives way to a portal registry now, before a second system makes it expensive. Adding a portal is one registry entry plus its client; landing and login code do not branch on a portal id. The spec is [012-portals](../specs/012-portals.md).

Each portal keeps its own attempt counter, so a rejected SIS login never spends another portal's attempts. This also fits the lockout guard in [011-login](../specs/011-login.md).

This does not change [ADR 0002](0002-device-only-data.md): data from every portal stays on the device, and the app still touches only the student's own accounts.
