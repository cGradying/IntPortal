use crate::*;

#[derive(Serialize)]
pub struct CoachLine {
    nudge: Nudge,
    line: String,
    key: String,
}

/// Today's one nudge, from deadlines, flashcards, free time and the target
/// GPA. `dismissed` holds the keys waved off today.
#[tauri::command(async)]
pub fn coach(state: tauri::State<'_, AppState>, now: Moment, dismissed: Vec<String>, busy: Option<Vec<Busy>>, utc_offset: Option<i32>) -> Res<Option<CoachLine>> {
    let store = state.store.lock().unwrap();
    let snap = store.load().map_err(err)?;
    let unix = unix_now();
    let offset = utc_offset.unwrap_or(MANILA_OFFSET);
    let stats = store.study_stats().map_err(err)?;
    let decks = store.decks().map_err(err)?;
    let mabini = store.mabini().map_err(err)?;
    let agenda = today::agenda(&snap.sessions, &snap.marks, now);
    let busy = busy.unwrap_or_default();
    let needed = snap.goals.target_gpa.zip(snap.grades.as_ref()).and_then(|(t, g)| grades::needed_average(&g.subjects, t).filter(|n| (1.0..5.0).contains(n)).map(|n| (n, t)));
    // The Due card's window (041 C7): overdue, then the next seven days. The plan looks three days on
    // (spec 042 C2), the deadline nudge two, and anything later keeps it from being a rest day (#244).
    let week = deadline::deadlines(&snap, &mabini, now, offset, 8);
    let day_of = |d: &deadline::Deadline| match d.due {
        deadline::Due::Day(day) => day,
        deadline::Due::At(u) => deadline::local_parts(u, offset).0,
    };
    let within = |d: &deadline::Deadline, days: i64| d.overdue || day_of(d) < now.date.add_days(days);
    let step = |d: &deadline::Deadline, subject: Option<String>| PlanStep { id: d.id.clone(), title: d.title.clone(), when: deadline::when_word(d, now, offset), subject, url: d.url.clone() };
    let plan_step = week.iter().find(|d| within(d, 4)).map(|d| step(d, d.subject.clone()));
    let later = week.iter().find(|d| !within(d, 2)).map(|d| step(d, Some(d.label().to_string()).filter(|l| !l.is_empty())));
    let signals = Signals {
        due_soon: week.iter().filter(|d| within(d, 2)).cloned().collect(),
        cards_due: decks.iter().map(|d| d.due(unix)).sum(),
        study_streak: study::current_streak(&stats, now.date),
        studied_today: stats.last_day == Some(now.date),
        free_minutes: today::free_minutes(&agenda.items, now, &busy),
        needed_average: needed,
        classes_left: agenda.items.iter().filter(|i| i.phase != today::Phase::Past).count(),
        gap: today::gaps(&agenda.items, now, &busy).into_iter().find(|g| g.minutes >= 30),
        plan_step,
        cards_by_subject: cards_by_subject(&decks, unix).into_iter().collect(),
        later,
    };
    Ok(coach::pick(&signals, &dismissed).map(|n| CoachLine { line: n.line(), key: n.key(), nudge: n }))
}

/// Flashcards due now, per subject code.
pub(crate) fn cards_by_subject(decks: &[Deck], unix: i64) -> std::collections::HashMap<String, usize> {
    let mut out = std::collections::HashMap::new();
    for d in decks {
        if let Some(code) = &d.subject {
            *out.entry(code.clone()).or_default() += d.due(unix);
        }
    }
    out
}

/// The target GPA and the program's units; either can be empty.
#[tauri::command(async)]
pub fn set_goals(state: tauri::State<'_, AppState>, goals: Goals) -> Res<Snapshot> {
    if goals.target_gpa.is_some_and(|g| !(1.0..=5.0).contains(&g)) {
        return Err("A target GPA runs from 1.00 to 5.00.".into());
    }
    if goals.program_units.is_some_and(|u| !(1.0..=400.0).contains(&u)) {
        return Err("Program units look off; check your curriculum.".into());
    }
    edit(&state, |s| s.goals = goals)
}

/// GPA, cumulative GPA, units, past terms and the target's reach.
#[tauri::command(async)]
pub fn standing(state: tauri::State<'_, AppState>) -> Res<Standing> {
    let snap = snapshot_of(&state)?;
    Ok(grades::standing(snap.grades.as_ref(), &snap.history, snap.goals))
}

/// Extra reminders the student turned on; a minute of the day, or empty for off.
#[derive(Deserialize, Default)]
pub struct ReminderPrefs {
    deadlines: Option<u16>,
    study: Option<u16>,
    /// Local minus UTC, in minutes.
    utc_offset: i32,
    /// Spec 042 C16; on unless the student turns them off.
    warm_up: Option<bool>,
    after_class: Option<bool>,
    brief: Option<bool>,
}

/// The next `days` of reminders, soonest first: classes (with a warm-up line
/// when cards are due), then everything else through the daily budget
/// (spec 042 C14, C15): deadlines, the Sunday brief, study days, notes after class.
#[tauri::command(async)]
pub fn reminders(state: tauri::State<'_, AppState>, now: Moment, lead: u16, days: u16, prefs: Option<ReminderPrefs>) -> Res<Vec<Reminder>> {
    let store = state.store.lock().unwrap();
    let snap = store.load().map_err(err)?;
    let prefs = prefs.unwrap_or_default();
    let decks = store.decks().map_err(err)?;
    let warm = if prefs.warm_up.unwrap_or(true) { cards_by_subject(&decks, unix_now()) } else { Default::default() };
    let mut out = if lead > 0 { today::reminders(&snap.sessions, &snap.marks, now, lead, days, &warm) } else { vec![] };
    let mut rest: Vec<(nudge::Kind, Reminder)> = vec![];
    // Two weeks reaches the end of the week a Sunday brief looks at.
    let list = deadline::deadlines(&snap, &store.mabini().map_err(err)?, now, prefs.utc_offset, i64::from(days).max(14));
    if let Some(minute) = prefs.deadlines {
        rest.extend(deadline::reminders(&list, now, minute, prefs.utc_offset, i64::from(days)).into_iter().map(|r| (nudge::Kind::Deadline, r)));
    }
    if prefs.brief.unwrap_or(true) {
        rest.extend(nudge::brief(&list, &snap.sessions, &snap.marks, now, prefs.utc_offset).filter(|r| r.date < now.date.add_days(i64::from(days))).map(|r| (nudge::Kind::Brief, r)));
    }
    if let Some(minute) = prefs.study {
        rest.extend(study::study_reminders(&decks, now, minute, i64::from(days), prefs.utc_offset).into_iter().map(|r| (nudge::Kind::Study, r)));
    }
    if prefs.after_class.unwrap_or(true) {
        let noted = notes::class_codes_with_text(&store.notes().map_err(err)?);
        rest.extend(nudge::after_class(&snap.sessions, &snap.marks, &noted, now, i64::from(days)).into_iter().map(|r| (nudge::Kind::AfterClass, r)));
    }
    out.extend(nudge::budget(rest, nudge::PER_DAY));
    out.sort_by_key(|r| (r.date, r.minute));
    Ok(out)
}
