# 000 SIS data map

**Status:** draft

What the app reads from PUP's SIS today, where each field lands, and which screens show it. This is the reference the portal specs ([012](012-portals.md)) and the login spec ([011](011-login.md)) cite. Mabini gets its own section when the user supplies captures.

## Hosts

Defined in `crates/intportal-core/src/sis/host.rs`.

| Fact | Value |
|---|---|
| Candidate pattern | exactly `sisN.pup.edu.ph` (`is_candidate`) |
| Default order | `sis8`, `sis1`, `sis2` (`DEFAULT_ORDER`) |
| Credential gate | https on `pup.edu.ph` or a subdomain (`is_trusted`) |
| Remembered host | `Snapshot.host`, tried first next time (`candidates`) |
| Not interchangeable | `sis1` signs in but never carries the schedule; `sis8` does |

Redirects follow only trusted URLs, at most 10 (`SisClient::new` in `sis/client.rs`).

## Pages read

All pages are server-rendered HTML under `https://<host>/student/`. Parsing is in `sis/scrape.rs`; requests are in `sis/client.rs`.

### Login form: `/student/`

`SisClient::sign_in` GETs the page, reads the form with `scrape::login_form`, and POSTs it.

| Field | Source |
|---|---|
| `studno` | `Credentials.student_number` |
| `SelectMonth`, `SelectDay`, `SelectYear` | `Credentials.birth_month / birth_day / birth_year` |
| `password` | `Credentials.password` |
| hidden fields (`csrf_token`, the `Login` submit value) | copied from the page unchanged |

Signed in means the login form is gone from the response (`scrape::has_login_form`, the `#studno` input). A rejection shows the SIS's own text from `.modal-body` or `.alert` (`scrape::page_message`), or a fallback line.

### Schedule: `/student/schedule`

`SisClient::schedule` → `scrape::schedule_rows` → `schedule::parse`.

| SIS column | `ScheduleRow` field | Then |
|---|---|---|
| Subject Code | `subject_code` | `ClassSession.subject_code` |
| Description | `description` | `ClassSession.description` |
| Unit | `unit` | not kept past the row |
| Schedule (first line) | `schedule_line` | parsed into `day`, `start`, `end` |
| Schedule (after `<br>`) | `faculty` | `ClassSession.faculty` |

The result is `Snapshot.sessions`. Shown by: Today, the week grid, class sheets, the glance, reminders and the phone's IntPortal calendar.

### Grades: `/student/grades`

`SisClient::grades` → `scrape::grades` → `grades::parse`.

| SIS column | `GradeRow` field |
|---|---|
| Subject Code, Description, Faculty Name | `subject_code`, `description`, `faculty` |
| Units, Sect Code | `unit`, `section_code` |
| Final Grade, Grade Status | `final_grade`, `grade_status` |

The page's `<dl>` summary (Admission Status, Scholastic Status, GPA) is kept raw in `GradeReport.summary`. The result is `Snapshot.grades`. Shown by: Grades, You, goals and standing.

### Term picker: the grades form

`SisClient::grade_history` finds the School Year and Semester selects by what their options look like, not by id (`scrape::term_picker`), then submits every year × semester pair. A term that fails or has no posted grades is skipped. Results, oldest first, are `Snapshot.history`.

## Where it lands

`Snapshot` in `crates/intportal-core/src/store.rs`:

| Field | From the SIS? |
|---|---|
| `sessions` | schedule page |
| `grades`, `history` | grades page and term picker |
| `host` | the host that last proved good |
| `last_synced` | written by the shell |
| `marks`, `colors`, `goals`, `syllabus` | the student's own layer; the SIS never sees them |

One encrypted store file per student number (`account_file`). The login itself lives in the platform keychain through `vault` in `src-tauri/src/lib.rs`, never in the store.

## Campus

The two-letter code inside the student number picks a campus label (`crates/intportal-core/src/campus.rs`). Only `MN` (Sta. Mesa) is confirmed; other codes are never guessed. The campus changes labels, never the host.

## Not read yet

To be filled from the user's captures. Candidates the app does not read today: enrolment status and assessment of fees, curriculum checklist, announcements, the student's profile page, and anything Mabini offers.

## Mabini

Not captured yet. Waiting on the user: screenshots, the sign-in fields, and the theme colours. Until then Mabini exists only as an "Opens soon" portal ([012](012-portals.md)).
