# PUPSISPortal

Native macOS dashboard for the [PUP Student Information System](https://sis8.pup.edu.ph/student/):
auto-fills and submits the real SIS login page, then pulls Schedule and
Grades out of it and renders them as native SwiftUI instead of a raw
embedded browser. Sibling project to [PUPSIS](https://github.com/cGradying/PUPSIS)
(same auto-login mechanism), but this one's the actual interface.

## Requirements

- macOS 13 or later
- Xcode / Swift toolchain 5.9+ (`xcode-select --install` if you don't
  already have the command line tools)

## Quick start

```sh
swift build -c release
Scripts/make_mac_app.sh
```

## Install

`Scripts/make_mac_app.sh`:

1. Builds the release binary.
2. Packages it as `PUPSISPortal.app` with a proper `Info.plist` and bundle
   identifier (`com.cgradying.pupsisportal`).
3. Ad-hoc code signs it.
4. Installs it to `~/Applications` (pass a different directory as the
   first argument to install elsewhere).
5. Forces Spotlight to index it immediately (`mdimport`).

## Usage

- **First run**: enter your student number, birth month/day/year, and
  password, then Save.
- **Every run after that**: signs in automatically, then shows a native
  dashboard — Home (sign-in status), Schedule, and Grades pulled from the
  real SIS pages. Enrollment, Accounts, Forms, and HDF aren't modeled
  natively yet, so those fall back to the real embedded SIS page.
- **Account menu** (menu bar): "Edit Credentials" to update saved details,
  "Sign Out" to remove them from this Mac.
- Light mode uses PUP's maroon/gold; dark mode uses the astra moon
  emerald/navy palette.

## Security

Credentials are stored only in the macOS Keychain (`security
find-generic-password -s ph.edu.pup.sis8.portal`) — never written to disk
in plaintext anywhere else.

## Scope

Only automates typing your own credentials into the official PUP login
form and reading your own Schedule/Grades pages in an embedded browser.
Neither scrapes other students' data, bypasses authentication, nor sends
anything anywhere besides the real PUP SIS server.

---

<div align="center">

[![Author: cGradying](https://img.shields.io/badge/cGradying-AUTHOR-10B981?style=for-the-badge&labelColor=0B1120)](https://github.com/cGradying)

</div>
