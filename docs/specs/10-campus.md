# 10 — Campus

Status: approved design (prototype v2). Small Core addition + three UI touch points.

## Facts (researched 2026-09-23)
- PUP has ~25 campuses and branches: Sta. Mesa (main); San Juan, Parañaque, Taguig, Quezon City,
  Caloocan; Mariveles (Bataan), Pulilan / Sta. Maria (Bulacan), Cabiao (Nueva Ecija); Maragondon /
  Alfonso (Cavite), Biñan / Calauan / San Pedro / Sta. Rosa (Laguna), Sto. Tomas / Talisay
  (Batangas), Mulanay / Lopez / Unisan (Quezon), Ragay (Camarines Sur), Bansud / Sablayan (Mindoro),
  Leyte. Source: Wikipedia, "Polytechnic University of the Philippines".
- Student numbers look like `YYYY-NNNNN-MN-0` (e.g. `2026-00000-MN-0`). **Only `MN` = Manila (Sta. Mesa) is confirmed**
  (public FOI example). Codes for other campuses are **unverified**; do not guess them in code.
- **All campuses use one SIS.** `sis1`/`sis2`/`sis8` are load-balanced copies, not per-campus
  systems. Campus never changes the server (see spec 00).

## Behaviour
`Core/Campus.swift` (pure):
```swift
struct Campus: Codable, Hashable { let code: String?; let name: String; let region: String }
enum CampusCatalog {
    static let all: [Campus]                      // list above; code "MN" only on Sta. Mesa
    static func code(fromStudentNumber: String) -> String?   // /^\d{4}-\d{5}-([A-Za-z]{2})-\d{1,2}$/, uppercased
    static func resolve(studentNumber: String, override: Campus?) -> CampusResolution
}
enum CampusResolution: Equatable { case known(Campus), unknownCode(String), incomplete, overridden(Campus) }
```
- `Preferences.campusOverride: Campus?` (Codable, UserDefaults). Cleared on sign-out.
- When a user picks a campus for an unknown code, store the override **and** remember the code →
  campus mapping locally (`Preferences.learnedCampusCodes[code] = name`) so the next sign-in
  resolves it. Nothing is sent anywhere.

## UI
1. **Sign-in panel** (spec 09): live line under Student Number — "MN · Sta. Mesa — campus found" /
   code chip + "Pick your campus" menu / "Your campus shows up as you type."
2. **Sidebar footer:** chip "MN · Sta. Mesa".
3. **Hub tag:** "PUP SIS / Sta. Mesa · via sis8".
4. **Settings ▸ Account ▸ Campus:** picker (all campuses) + hint "Read from your student number.
   Only the MN code is confirmed; pick yours if it's wrong. Every campus uses the same SIS."

## Acceptance criteria
- [ ] `CampusTests`: MN → Sta. Mesa; `2026-00000-TG-0` → `.unknownCode("TG")`; malformed →
      `.incomplete`; override wins; learned code resolves on next call; one- and two-digit suffix
      both accepted.
- [ ] Campus appears in the three places above and updates when changed in Settings. Evidence:
      screenshots.
- [ ] Sign-out clears the override and learned codes. Evidence: test.

## Out of scope
Per-campus theming, campus-specific SIS hosts, fetching campus data from PUP.
