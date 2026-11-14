use crate::*;

/// Made-up eMabini data for review builds, so Mabini screens can be shown
/// without anyone's account.
pub(crate) fn demo_mabini(now: i64) -> MabiniData {
    use intportal_core::mabini::parse::{Course, CourseGrade, Deadline};
    let course = |id: u64, subject: &str, progress: Option<f64>| Course {
        id,
        fullname: format!("{subject}_First Sem 2627_BSIT 1-A"),
        subject: subject.into(),
        term: "First Sem 2627".into(),
        section: "BSIT 1-A".into(),
        start: now - 40 * 86_400,
        end: now + 80 * 86_400,
        progress,
        url: format!("https://emabini.pup.edu.ph/course/view.php?id={id}"),
    };
    let due = |id: u64, name: &str, course_id: u64, course: &str, days: f64| Deadline {
        id,
        name: name.into(),
        course_id,
        course: course.into(),
        kind: "assign".into(),
        due: now + (days * 86_400.0) as i64,
        overdue: days < 0.0,
        url: format!("https://emabini.pup.edu.ph/mod/assign/view.php?id={id}"),
    };
    MabiniData {
        courses: vec![
            course(11, "Physical Activity Towards Health and Fitness 1", Some(40.0)),
            course(12, "Filipinolohiya at Pambansang Kaunlaran", Some(65.0)),
            course(13, "Mathematics in the Modern World", None),
        ],
        deadlines: vec![
            due(1, "PETA 1 is due", 11, "Physical Activity Towards Health and Fitness 1", -0.5),
            due(2, "Pagsusulit 1 closes", 12, "Filipinolohiya at Pambansang Kaunlaran", 0.4),
            due(3, "Problem Set 2 is due", 13, "Mathematics in the Modern World", 3.0),
        ],
        grades: vec![
            CourseGrade { course_id: Some(11), name: "Physical Activity Towards Health and Fitness 1_First Sem 2627_BSIT 1-A".into(), grade: None },
            CourseGrade { course_id: Some(12), name: "Filipinolohiya at Pambansang Kaunlaran_First Sem 2627_BSIT 1-A".into(), grade: Some("1.75".into()) },
            CourseGrade { course_id: Some(13), name: "Mathematics in the Modern World_First Sem 2627_BSIT 1-A".into(), grade: None },
        ],
        last_synced: Some(now as u64),
    }
}

/// Review builds only: a fake week and term so every screen can be seen
/// without an SIS account.
#[tauri::command(async)]
pub fn demo(state: tauri::State<'_, AppState>, today: Date) -> Res<Snapshot> {
    if !cfg!(debug_assertions) {
        return Err("demo is only in review builds".into());
    }
    DEMO.store(true, Ordering::Relaxed);
    open_account(&state, "demo")?;
    let s = |code: &str, desc: &str, day: Weekday, start: u16, end: u16| ClassSession {
        subject_code: code.into(),
        description: desc.into(),
        faculty: "SANTOS, JUAN".into(),
        day,
        start,
        end,
        occurrence: 0,
    };
    let wd = today.weekday();
    let sessions = vec![
        s("COMP 20073", "Data Structures and Algorithms", wd, 7 * 60 + 30, 9 * 60),
        s("GEED 10053", "Purposive Communication", wd, 10 * 60 + 30, 12 * 60),
        s("MATH 20013", "Discrete Structures", wd, 13 * 60, 14 * 60 + 30),
        s("COMP 20083", "Object-Oriented Programming", wd, 16 * 60, 19 * 60),
        s("PATHFIT 2", "Physical Activity Towards Health and Fitness 2", today.add_days(1).weekday(), 8 * 60, 10 * 60),
        s("GEED 10103", "Filipinolohiya at Pambansang Kaunlaran", today.add_days(1).weekday(), 13 * 60, 16 * 60),
    ];
    let g = |code: &str, desc: &str, units: &str, grade: &str| grades::GradeRow {
        subject_code: code.into(),
        description: desc.into(),
        faculty: "SANTOS, JUAN".into(),
        unit: units.into(),
        section_code: "1".into(),
        final_grade: grade.into(),
        grade_status: if grade.is_empty() { String::new() } else { "Passed".into() },
    };
    let rows = [
        g("COMP 20073", "Data Structures and Algorithms", "3", "1.25"),
        g("GEED 10053", "Purposive Communication", "3", "1.50"),
        g("MATH 20013", "Discrete Structures", "3", ""),
        g("COMP 20083", "Object-Oriented Programming", "3", ""),
        g("PATHFIT 2", "Physical Activity Towards Health and Fitness 2", "2", "1.00"),
        g("GEED 10103", "Filipinolohiya at Pambansang Kaunlaran", "3", ""),
    ];
    let summary = [("Admission Status", "Freshman"), ("Scholastic Status", "Regular"), ("Course", "BSCS")]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
    let history = [("2025-2026", "First Semester", ["1.50", "1.75", "1.25"]), ("2025-2026", "Second Semester", ["1.25", "1.50", "1.25"])]
        .into_iter()
        .map(|(y, sem, gs)| GradeReport {
            subjects: grades::parse(&[g("COMP 001", "Intro", "3", gs[0]), g("GEED 004", "Math", "3", gs[1]), g("GEED 005", "Comm", "3", gs[2])]),
            summary: Default::default(),
            school_year: Some(y.into()),
            semester: Some(sem.into()),
        })
        .collect();
    // Only the SIS side is fake; the student's own marks, goals and pages stay.
    let snap = Snapshot {
        sessions,
        grades: Some(GradeReport { subjects: grades::parse(&rows), summary, school_year: Some("2026-2027".into()), semester: Some("First Semester".into()) }),
        history,
        host: Some("sis8.pup.edu.ph".into()),
        last_synced: Some(now_secs()),
        ..snapshot_of(&state)?
    };
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    state.store.lock().unwrap().save_mabini(&demo_mabini(unix_now())).map_err(err)?;
    Ok(snap)
}
