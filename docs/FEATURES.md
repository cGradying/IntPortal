# Features

What IntPortal does, tab by tab, as of version 0.2.0. This page is for students; how the app is built is in [ARCHITECTURE.md](ARCHITECTURE.md).

IntPortal is an independent student project, not affiliated with PUP. Sign in only with your own account.

## Signing in

- **A welcome first.** A new student sees the portal and three tabs to touch before any form. **Inside** opens the portal's peek on Today, Schedule, Grades or Study, with sample data. **What it does** has LAR explain reminders, deadlines, offline use, privacy and his nudges. **Make it yours** tries six dark looks on the landing; the one you pick stays after you sign in.
- **Portals.** SIS holds your classes and grades. Mabini (eMabini, PUP's learning system) holds your courses, deadlines and course grades. Sign in to one or both. The plaque under the portal opens the portal wall: SIS and eMabini first, then every PUP school A to Z.
- **Is the SIS up?** A chip under the portal says when the SIS isn't answering. It checks without sending your login; tap it to check again.
- **Forgot password** opens the portal's own reset page, and **How** explains where your login is kept.
- **SIS login.** Student number, birthdate and password.
- **Mabini login.** Your student number and your eMabini password.
- **Look around first** opens the whole app with sample classes and grades, no account needed.
- **Your account stays safe.** Each tap signs in once. After three tries in 15 minutes the app waits and tells you when you can try again, and it never retries a rejected password on its own. A wrong password can't get your PUP account locked by the app.
- **First run.** Choose **Light, no AI** or **With AI** (see IntAssis below), and turn on reminders if you want them.

## Today

- **Up next.** Your next class with a countdown, or "in session" while it runs.
- **Today's classes.** In order, with the free time between them. Your own calendar events count as busy time, if you allow it.
- **Tomorrow starts with.** The first class of tomorrow and its time.
- **Due.** One card for deadlines from your syllabus outlines, your Mabini courses and your own. Tap **Done** beside one (or long-press it) and it drops into "Done this week", with Undo for 5 seconds. **Add** your own by typing it or scanning a photo of it.
- **Your GPA at a glance.** This term and overall.
- **One nudge from LAR.** A single tip a day: a deadline, cards due, a free gap you can use, or your target GPA. Dismiss it and it stays gone.
- **Pull to sync.** Pull down to fetch fresh data from the SIS and Mabini.

## Schedule

- **Day and week.** Your classes on a grid with a line at the current time.
- **Tap a class** to open it, then:
  - say how it meets this time: **In person**, **Online** or **Vacant**, for **This week only** or **Every week this term**;
  - **Change its time** for one week or every week, and go **Back to SIS time** later;
  - pick its **Colour**;
  - open **Syllabus & grading** and its notes.
- **Hide vacant classes** clears the week of classes you marked vacant.

## Grades

- **Every term** with a real units-weighted GPA. Pending, INC and DRP grades don't count toward it.
- **Trend and progress.** Your GPA across terms with guides at 1.00, 1.50 and 2.00, and units done out of your program's total. VoiceOver reads the trend as a sentence.
- **All passed.** A pill once every subject this term is posted and passed.
- **Target GPA.** Set a goal and see what you need on the rest of the term to reach it, and whether it's still in reach. A personal best gets confetti.
- **Mabini grades.** Course grades from eMabini, next to the SIS ones.

## Study

- **Decks of flashcards** per subject. Add cards by hand or paste "front - back" lines.
- **Spaced repetition.** Cards come back when you're about to forget them (FSRS). Each rating shows when the card would come back (10m, 1d, 3d…), and the end of a round shows your score and each card's next review.
- **Review everything due** across all your decks at once.
- **Three ways to study.** Flip the card, type the answer, or pick from choices.
- **Due now, streak and Done.** How many cards are due, your daily streak, and your reviews over the last 7 days.
- **Why?** After a wrong answer, LAR explains it using your class notes (needs IntAssis).
- **Cards from a note** with IntAssis: review them before you save.

## Subjects, syllabus and notes

- **Outline.** Paste a course outline and IntPortal finds the lectures, quizzes, exams and projects by week and date. Check items off as you go.
- **Grading.** Add the components (quizzes 30%, exams 40%…), enter your scores, and see the average you need for the grade you're aiming for.
- **Notes.** Formatted Markdown with a toolbar, templates, checklists you tick without the keyboard, photos, and a page look (size, font, spacing, paper). One note per class that carries across weeks, a note per day, named notes and notebooks per subject. Search them, make cards from one, and export one or all as Markdown.

## Mabini

- **Courses and deadlines.** Every deadline in one list, overdue first, then every course you're enrolled in with its progress and grade.
- **Open in eMabini.** Tap a course or a deadline to open it on the eMabini site.

## IntAssis (optional)

LAR, the Lakbay-Aral Robot, answers with a small model that runs on your phone. Nothing is sent anywhere.

- **Ask about your day.** Classes today, what's due, how your grades stand. Exact questions are answered straight from your data.
- **Ask about your notes.** Answers cite the notes they came from; tap a source to open it.
- **Ask AI in a note.** Summarize, tidy or explain a note, or ask it a question, then insert or replace.
- **Suggestions you confirm.** LAR can offer to add a note, set a reminder or make cards. Nothing changes until you tap to confirm.
- **Filipino and Taglish** questions work, including "bukas" and "sa Lunes".
- **Your choice of model.** The model downloads only when you pick **With AI**, and you can delete it from You.

## Reminders and the phone

- **Class reminders** before each class, at the time you choose.
- **Deadline reminders** the evening before a syllabus deadline, and **study reminders** on days cards are due.
- **Next class outside the app.** A Live Activity on the Lock Screen and in the Dynamic Island on iPhone, and a Live Update in the status bar on Android. In You › Reminders you choose whether it always shows, shows only after you leave the app (the default, so it goes away when you open IntPortal), or never.
- **Home-screen widget** on both.
- **Calendar.** An IntPortal calendar in your phone's calendar app holds your classes and stays in sync. **Add classes to calendar** also shares them as an `.ics` file.

## You

- **Account and look.** Which portals you're signed in to, when they last synced, and the colour theme ("rooms").
- **App lock.** Face ID or fingerprint before the app opens.
- **Your notes.** Search, open, start a new one, or export them all.
- **Sign out** of the SIS or Mabini, or **Erase everything** on the phone.

## Privacy

- Your data stays on the phone. There is no IntPortal server.
- Your logins are in the phone's keychain (the Keystore on Android), never in the app's files.
- Each student's data is its own encrypted file with its own key, so two students can share a phone.
- The AI runs on the phone; its model comes from a pinned download checked against a fingerprint.
