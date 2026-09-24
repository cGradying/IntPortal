import Foundation

/// A sample-data launch for screenshots and live checks, started with
/// `-IntPortalDemo`. Debug builds only; in Release `isOn` is a constant
/// `false` and none of the data below is compiled in.
///
/// It never reads the Keychain or contacts the SIS, keeps its settings in
/// its own defaults suite, and refuses to start unless `CFFIXED_USER_HOME`
/// moves Application Support somewhere disposable, so a demo run can't read
/// or overwrite a real student's notes, decks or cached schedule.
enum Demo {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-IntPortalDemo")
    #else
    static let isOn = false
    #endif

    /// Preferences' store. A fresh suite per demo launch, so every run starts
    /// from the same defaults.
    static let defaults: UserDefaults = {
        #if DEBUG
        if isOn, let suite = UserDefaults(suiteName: "IntPortalDemo") {
            suite.removePersistentDomain(forName: "IntPortalDemo")
            return suite
        }
        #endif
        return .standard
    }()
}

#if DEBUG
extension Demo {
    /// `-IntPortalScreen schedule|today|grades` opens that screen at launch.
    static var screen: Destination? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-IntPortalScreen"), i + 1 < args.count else { return nil }
        return Destination(rawValue: args[i + 1])
    }

    @MainActor
    static func seed(_ app: AppState) {
        guard ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil else {
            fatalError("-IntPortalDemo needs CFFIXED_USER_HOME set to a scratch folder so it can't touch real app data.")
        }
        app.credentials = Credentials(studentNumber: "2026-00000-MN-0", birthMonth: 3, birthDay: 14, birthYear: 2007, password: "")
        app.portal.sessions = sessions
        app.portal.lastUpdated = .now
        app.portal.grades = grades
        app.preferences.notificationsEnabled = false
    }

    /// The prototype's sample week (docs/specs/prototypes), sample names only.
    static let sessions: [ClassSession] = [
        ("GEED 005", "Purposive Communication", Weekday.monday, 900, 1080),
        ("GEED 032", "Filipinolohiya at Pambansang Kaunlaran", .monday, 1080, 1260),
        ("COMP 002", "Computer Programming 1", .wednesday, 540, 720),
        ("GEED 020", "Politics, Governance and Citizenship", .wednesday, 1080, 1260),
        ("PATHFIT 1", "Movement Competency Training", .thursday, 840, 960),
        ("COMP 001", "Introduction to Computing", .friday, 810, 990),
        ("COMP 002", "Computer Programming 1", .saturday, 990, 1110),
        ("CWTS 001", "Civic Welfare Training Service 1", .sunday, 780, 1080),
    ].map { ClassSession(subjectCode: $0.0, description: $0.1, faculty: "Prof. Sample", day: $0.2, start: $0.3, end: $0.4) }

    static let grades = GradeReport(
        lastUpdated: .now,
        subjects: [
            ("GEED 003", "The Contemporary World", 3.0, "1.25"),
            ("GEED 006", "Art Appreciation", 3.0, "1.00"),
            ("GEED 007", "Science, Technology and Society", 3.0, "1.50"),
            ("GEED 008", "Ethics", 3.0, "1.25"),
            ("PATHFIT 00", "Dance Fundamentals", 2.0, "1.00"),
        ].map {
            SubjectGrade(subjectCode: $0.0, description: $0.1, faculty: "Prof. Sample", units: $0.2,
                         sectionCode: "", finalGrade: $0.3, gradeStatus: "Passed")
        },
        summary: ["GPA": "1.23"],
        schoolYear: "2025-2026",
        semester: "Second Semester"
    )
}
#endif
