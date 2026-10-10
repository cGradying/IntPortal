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

## Mabini (eMabini)

From public pages, 2026-10-11; not yet checked against a signed-in account.

| Fact | Value |
|---|---|
| What it is | eMabini, the PUP Open University System's learning portal, run on Moodle (the "moove" theme) |
| Address | `https://emabini.pup.edu.ph/`, login at `/login/index.php`, reset at `/login/forgot_password.php` |
| Login form | `username`, `password`, and a hidden `logintoken`; no birthdate |
| Username | the student number, lowercase, dashes removed, for example `202412345mn0` (the portal's home page) |
| Password | issued by the Open University office, with a default that must be changed on first login (FAQ) |
| Brand colour | `#700000`, the theme's primary: the same maroon as the SIS |
| Other | an eMabini mobile app exists; the site also serves guest pages |
| Who | enrolled Open University students, plus staff roles |
| Help | `emabini.support@pup.edu.ph` |

Sources: the portal's login and home pages; the PUP SINTA FAQ "OUS: PUP eMabini Learning Portal (LMS)". The FAQ and the home page differ on the username format; the home page is newer.

### Checked against a signed-in account (2026-10-11)

Read-only, on the student's own account, by the student signing in; no values are recorded here.

**Sign-in.** `GET /login/index.php` returns a form with a hidden `logintoken`, `username` and `password`. POST all three. A signed-in page carries `"sesskey":"…"` in its inline config and a logout link `/login/logout.php?sesskey=…`. The sesskey is per session and is needed for the JSON calls below.

**Pages and calls**

| Data | How | Shape |
|---|---|---|
| Courses | `POST /lib/ajax/service.php?sesskey=…&info=core_course_get_enrolled_courses_by_timeline_classification` with `args {offset:0, limit:0, classification:"all", sort:"fullname", customfieldname:"", customfieldvalue:""}` | `data.courses[]` with `id`, `fullname`, `shortname`, `startdate`, `enddate`, `progress`, `hasprogress`, `viewurl`, `coursecategory`, `isfavourite`, `hidden` |
| Deadlines | `POST` the same endpoint, method `core_calendar_get_action_events_by_timesort`, `args {limitnum, timesortfrom}` | `data.events[]` with `name` ("X is due"), `modulename` (`assign`, …), `eventtype` (`due`), `timesort`, `overdue`, `course`, `url`, `action` |
| Course grades | `GET /grade/report/overview/index.php` | table `#overview-grade`, headers `Course name`, `Grade`; one row per course; the name cell links to `/course/user.php?mode=grade&id=N&user=N`; an ungraded course shows `-` |
| Calendar page | `GET /calendar/view.php?view=month` or `upcoming` | server-rendered; the JSON call above is steadier |

The request body is a JSON array: `[{"index":0,"methodname":"…","args":{…}}]`, and the reply is an array with `error` and `data`. Moodle's AJAX service takes the logged-in cookies plus the sesskey; no separate API token is needed.

**Course names** follow `<Subject>_<Term> <Year code>_<Program section>`, for example `…_First Sem 2627_…`. The subject, term and section can be split on `_`. `shortname` and `idnumber` need a look at more courses before relying on them.

**Menu**: Dashboard `/my/`, My courses `/my/courses.php`, Grades, Calendar, Messages, Private files, Reports, Preferences.

**Fit with the app.** A course is the closest thing to a subject; deadlines are the new data the SIS never had. Mapping to `Snapshot` is a later spec.

Not read yet: course contents (activities, files), quiz and assignment detail, messages, notifications, per-course grade items, and whether `core_course_get_contents` is reachable without an API token.
