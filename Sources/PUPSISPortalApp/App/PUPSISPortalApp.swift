import AppKit
import Sparkle
import SwiftUI

/// The Schedule screen's controls, lifted out of `CalendarView` so the floating
/// nav island can drive them. Week nav / scale / show-cancelled are plain
/// state the island mutates directly; year-step and new-event are intents the
/// view consumes (they need `CalendarView`'s week/editor context).
@MainActor
final class ScheduleModel: ObservableObject {
    @Published var scale: CalendarScale = .week
    @Published var weekOffset = 0
    @Published var showCancelled = true
    /// Island → view: −1 / +1 to step by the current scale; the view resets it to 0.
    @Published var stepIntent = 0
    /// Island → view: bumped to request a new event at the default slot.
    @Published var newEventIntent = 0
}

/// Which side of Notebook is showing — mutated by the island's segmented
/// control when `.notebook` is open, same pattern as `ScheduleModel`.
@MainActor
final class NotebookModel: ObservableObject {
    @Published var tab: NotebookTab = .vault
}

enum NotebookTab: String, CaseIterable, Identifiable {
    case vault
    case quizzes
    case syllabus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .vault: "Vault"
        case .quizzes: "Quizzes"
        case .syllabus: "Syllabus"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let schedule = ScheduleModel()
    let notebook = NotebookModel()
    @Published var credentials: Credentials?
    @Published var isEditing = false

    let portal = PortalController()
    let preferences = Preferences()
    let calendar = CalendarBridge()
    let notes = NotesStore()
    let syllabus = SyllabusStore()
    let quizzes = QuizStore()
    let generation = GenerationCenter()
    lazy var googleAuth = GoogleAuth { [preferences] in preferences.googleClientID }
    lazy var googleClient = GoogleCalendarClient(auth: googleAuth)

    /// The current minute, republished on the minute boundary. The menu bar's
    /// "next class" has no view of its own to hang a `TimelineView` on, so the
    /// clock lives here where both the menu bar and any window can read it.
    @Published var now = Date()
    private var clock: Timer?

    /// Which destination the window shows, and whether Settings is up. App-level
    /// so the menu commands (⌘1/2/3, ⌘,) can drive them, not just the view.
    @Published var selection: Destination = .schedule
    @Published var showingSettings = false

    /// The nav island's placement. Launch shows the island centred (a home
    /// launcher); opening a destination flies it to the top and reveals the
    /// screen. The island's home mark flips it back.
    @Published var isHome = true

    /// Sparkle's own delegate shim — `availableVersion` drives the footer
    /// badge and Settings › About. See `UpdaterBridge` for why it isn't
    /// folded directly into `AppState`.
    let updaterBridge = UpdaterBridge()

    /// Starts Sparkle's own launch-time background check and scheduler
    /// (`SUEnableAutomaticChecks` in Info.plist). `lazy` so construction —
    /// and its `startingUpdater: true` side effect — happens once, on first
    /// touch, rather than as an unconditional part of `init()`.
    private(set) lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: updaterBridge, userDriverDelegate: nil
    )

    /// The note key the user is currently looking at, mirrored up from
    /// whichever screen has one open (today: `AgendaView`) — see the comment
    /// at its `.onChange`/`.onAppear` there. Read by the assistant to answer
    /// "summarize this note" without the model needing a key it was never told.
    @Published var openNoteKey: String?

    /// The "Add dated entry" menu's labels for whichever note is open, mirrored
    /// up the same way `openNoteKey` is — non-nil only for a shared per-subject
    /// `class:` note. See `AgendaView.addDateOptions(for:)`.
    @Published var noteAddDateOptions: (next: String, today: String)?

    /// One shared bridge to whichever `WKWebView` the open note is rendering.
    /// Was a `@StateObject` local to `WebNoteEditor` before the floating deck
    /// (wayfinder ticket #7) needed to drive editor commands from outside
    /// that view entirely — same reasoning as `openNoteKey` above.
    let noteBridge = WebNoteBridge()

    /// The floating assistant's own conversation state.
    let assistant = AssistantSession()

    /// The assistant's **own** `EventEditor`, separate from `CalendarView`'s.
    /// `EventEditor.undoManager` is only wired while `CalendarView` is on
    /// screen (`Views/CalendarView.swift`), so an edit made from the assistant
    /// while looking at Grades or Today would otherwise be un-undoable. Both
    /// editors share the same underlying `CalendarBridge`, so an assistant-made
    /// event still shows up once that bridge reloads.
    lazy var assistantEditor: EventEditor = {
        let editor = EventEditor(bridge: calendar)
        editor.onChange = { [weak self] in self?.reloadCalendarForAssistant() }
        return editor
    }()

    private func reloadCalendarForAssistant() {
        let thisWeek = Weekday.weekStart(containing: .now)
        let viewedWeek = Calendar.current.date(
            byAdding: .day, value: schedule.weekOffset * 7, to: thisWeek
        ) ?? thisWeek
        calendar.load(weekStart: viewedWeek, calendarIDs: preferences.visibleCalendarIDs)
    }

    /// Open a destination from the island or a menu command: select it and
    /// leave home so the island glides to the top.
    func open(_ destination: Destination) {
        selection = destination
        isHome = false
    }

    init() {
        FontLibrary.registerBundledFonts()
        // No-op on the lite build (no `models/` in the bundle) and on any
        // launch after the first (already adopted) — see its own doc comment.
        ModelCatalog.adoptBundledModels()
        credentials = KeychainStore.load()
        isEditing = credentials == nil
        isHome = preferences.islandStartHome
        startClock()
        _ = updaterController // force the lazy: starts Sparkle's scheduler now, not on first UI touch
        observeTermination()
    }

    /// Frees what the assistant was using the moment the app quits, rather
    /// than leaving it resident — confirmed neither happened before this:
    /// `OllamaClient.unload` only ever fired on a manual Settings action, and
    /// `llama-server` had no relationship with the app at all, so a hand-
    /// started one could (and did) outlive the app entirely. `willTerminate`
    /// is the one notification all three quit paths converge on — ⌘Q, the
    /// Dock, and the menu-bar Quit button's `NSApp.terminate(nil)` — so this
    /// one observer covers all of them without an `NSApplicationDelegate`.
    private func observeTermination() {
        // `queue: nil` — not `.main`. `.main` doesn't mean "run synchronously
        // on the main thread"; it means "enqueue onto `OperationQueue.main`
        // and run on a *later* run-loop turn", which during termination may
        // never come before the process exits. `nil` is what actually
        // delivers synchronously on the posting thread — confirmed the real
        // bug behind the fix not working: it was there, just never ran.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            // AppKit posts lifecycle notifications on the main thread, and
            // `queue: nil` above delivers synchronously on the posting
            // thread — so this really is the main actor already, safe to
            // assume rather than hopping through `Task`, which still
            // wouldn't be guaranteed to get scheduled before exit.
            MainActor.assumeIsolated {
                // `llama-server` holds no state to unload — a clean SIGTERM
                // here is the whole story, unlike Ollama's separate
                // idle-timeout-driven unload this used to also need.
                LlamaServerManager.shared.stop()
            }
        }
    }

    /// Fires on each :00 rather than 60s after launch, so "in 25 min" flips when
    /// the wall clock does. `.common` keeps it ticking while a menu is open.
    private func startClock() {
        let fromNextMinute = NowLine.nextMinute.timeIntervalSinceNow
        clock = Timer.scheduledTimer(withTimeInterval: max(fromNextMinute, 1), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.now = Date() }
                }
                self?.clock.map { RunLoop.main.add($0, forMode: .common) }
            }
        }
        clock.map { RunLoop.main.add($0, forMode: .common) }
    }

    /// The next class right now, or `nil`. Vacant meetings are excluded by
    /// **this-week** status — the same per-week rule the day list and the grid
    /// use — so the menu bar never advertises a class the user cancelled this
    /// week. (Reminders stay term-wide in `Notifier`: a weekly-repeating trigger
    /// can't skip a single week.)
    var upcoming: NextClass.Upcoming? {
        NextClass.next(
            in: portal.sessions, at: now,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            },
            time: { session, date in
                preferences.time(for: session, on: Weekday.weekStart(containing: date))
            }
        )
    }

    /// Refresh from anywhere — the app menu, the menu bar — and reschedule
    /// reminders afterward. Routed through here (not the window) so a refresh
    /// with the window closed still keeps the OS's pending reminders in step.
    func refresh() async {
        await portal.loadSchedule()
        await portal.loadGrades()
        Notifier.shared.sync(portal.sessions, preferences)
    }

    func save(_ credentials: Credentials) {
        try? KeychainStore.save(credentials)
        self.credentials = credentials
        isEditing = false
        portal.status = .idle
    }

    func signOut() {
        KeychainStore.delete()
        // Both caches are this student's own data; signing out has to take them
        // off disk too, not just off screen.
        ScheduleStore.delete()
        GradesStore.delete()
        credentials = nil
        isEditing = true
        portal.status = .idle
        portal.sessions = []
        portal.lastUpdated = nil
        portal.refreshError = nil
        portal.grades = nil
        portal.gradesError = nil
        portal.gradeHistory = []
    }
}

/// The three main destinations. Settings is no longer one of these — it's a
/// sheet behind the gear button.
enum Destination: String, CaseIterable, Identifiable {
    case schedule
    case today
    case grades

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .today: "Notebook"
        case .grades: "Grades"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: "calendar"
        case .today: "list.bullet.rectangle"
        case .grades: "graduationcap"
        }
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    /// Flipped true just after the chrome band mounts, so it dithers in rather
    /// than appearing whole. Reset by the band's own `onAppear` each time a
    /// destination opens (the band's `if` removes/reinserts it from the tree).
    @State private var bandResolved = false
    /// Flipped true just after the home title mounts, so it fades/rises in
    /// rather than appearing whole. Reset on every home visit, same pattern
    /// as `bandResolved`.
    @State private var titleResolved = false
    /// Clears the nav island's fixed-size home content above it. A plain
    /// constant rather than `Theme.Chrome` — one call site, not a repeated
    /// value the way the chrome-strip height is.
    private let homeTitleOffset: CGFloat = -86

    /// `Theme.Chrome.topStrip` scaled by UI Scale — grown, not stretched
    /// (`Typography` above does the equivalent for text): with the old root
    /// `.scaleEffect` gone, nothing else makes this strip track the zoom
    /// level automatically.
    private var topStrip: CGFloat { Theme.Chrome.topStrip * preferences.uiScale }

    /// The floating month calendar (`CalendarView`) blurs/dims the grid and
    /// sidebar itself, but it's inset below this top strip and has no reach
    /// above it — this is what extends the same treatment to the chrome
    /// band, so the whole screen behind the popup dims, not just the part
    /// under `CalendarView`. The island itself is drawn after this in
    /// z-order, so it's untouched.
    private var showingMonthOverlay: Bool {
        appState.selection == .schedule && appState.schedule.scale == .year
    }

    var body: some View {
        content
            // Reaches both branches of `content` (login screen and the main
            // app) — the login screen's own circular gear button sets this
            // same flag, so one sheet definition covers both.
            .sheet(isPresented: $appState.showingSettings) { settingsSheet }
            .frame(minWidth: 900, minHeight: 600)
            .background(TrafficLights(autoHide: preferences.trafficLightsAutoHide))
            .environment(\.palette, preferences.theme.palette(for: systemScheme))
            .environment(\.typography, Typography(preferences.fontChoice, scale: preferences.uiScale))
            .environment(\.uiScale, preferences.uiScale)
            // Keeps native controls (fields, pickers, popovers) in step with a
            // theme the user picked against their system setting.
            .preferredColorScheme(preferences.theme.colorScheme)
            // Same reasoning as CalendarView wiring its own EventEditor's
            // undoManager: SwiftUI only hands one out via the environment
            // inside a view, so the assistant's editor (a plain object on
            // AppState) has to be handed it explicitly, once, here.
            .onAppear { appState.assistantEditor.undoManager = undoManager }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isEditing || appState.credentials == nil {
            // No nav before sign-in: there is nowhere to go yet.
            CredentialsView(
                existing: appState.credentials,
                onSave: appState.save,
                showingSettings: $appState.showingSettings
            )
        } else if let credentials = appState.credentials {
            ZStack(alignment: .top) {
                // Base: a calm wash at home, the screen (inset below the floating
                // island) once open. Cross-fades under the gliding island.
                Group {
                    if appState.isHome {
                        ZStack {
                            preferences.theme.palette(for: systemScheme).canvasWash
                            // Animated static, behind everything else at home —
                            // the one other place accent tint is allowed to show,
                            // and only faintly. See HomeNoiseField's own doc
                            // comment for why this is safe to run continuously.
                            HomeNoiseField(color: preferences.theme.palette(for: systemScheme).accent)
                        }
                        .ignoresSafeArea()
                    } else {
                        destination(for: credentials)
                            .padding(.top, topStrip) // clear the slim top bar
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // The home wordmark — mounts fresh (and replays its entrance)
                // every time isHome becomes true, same as the chrome band below.
                if appState.isHome {
                    Text("Student IntPortal")
                        .font(Typography(preferences.fontChoice, scale: preferences.uiScale).hero)
                        .foregroundStyle(preferences.theme.palette(for: systemScheme).accent)
                        .opacity(titleResolved ? 1 : 0)
                        .offset(y: titleResolved ? 0 : 8)
                        .onAppear { titleResolved = false }
                        .animation(Motion.arrival(reduced: reduceMotion), value: titleResolved)
                        .task { titleResolved = true }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: homeTitleOffset)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                // A pixel-dither strip textures the otherwise-flat top bar. Clipped
                // slightly inside the window's own rounded corner so individual
                // dither cells are never sliced mid-square by the window mask.
                if !appState.isHome {
                    // Pixel gradient, not a uniform speckle — dense at the top,
                    // fading toward the destination below it.
                    DitherFill(
                        color: preferences.theme.palette(for: systemScheme).accent.opacity(0.6),
                        ramp: .topDown,
                        density: bandResolved ? 1 : 0
                    )
                    .frame(height: topStrip)
                    // The dither's own fade is density-per-cell — an ordered
                    // Bayer matrix only has 16 discrete thresholds, so density
                    // hits zero (no more dots to drop) well before the band's
                    // bottom edge, and the fade reads as a hard stop instead
                    // of thinning out. A real per-pixel alpha gradient on top
                    // smooths that regardless of how sparse the dots get.
                    .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .blur(radius: showingMonthOverlay ? 14 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .top) {
                        if showingMonthOverlay {
                            Color.black.opacity(0.25)
                                .frame(height: topStrip)
                                .onTapGesture { appState.schedule.scale = .week }
                                .transition(.opacity)
                        }
                    }
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: Theme.Chrome.windowRadius,
                            topTrailingRadius: Theme.Chrome.windowRadius
                        )
                    )
                    .transition(.opacity)
                    .onAppear { bandResolved = false }
                    .animation(Motion.arrival(reduced: reduceMotion), value: bandResolved)
                    .task { bandResolved = true }
                }

                // Invisible titlebar-style drag strip: moves the window in place of
                // background dragging (which fought the calendar's create-drag).
                // Below the island in z-order, so island buttons still win.
                WindowDragArea()
                    .frame(height: topStrip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // The island itself never re-mounts — it *glides* from centre (home)
                // to the top (open), so opening reads as a move/expand, not a fade.
                // Hover morph keeps working because it's one live view throughout.
                NavIsland(appState: appState, schedule: appState.schedule, notebook: appState.notebook, preferences: preferences)
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: appState.isHome ? .center : .top)
                    .padding(.top, appState.isHome ? 0 : 4)

                // Floating, reachable from every screen. Always mounted now —
                // it doubles as the Notebook note toolbar (wayfinder ticket
                // #7), which must keep working with the AI beta toggle off;
                // `AssistantFloating` renders `EmptyView` itself whenever
                // neither the toolbar nor chat has anything to show.
                AssistantFloating(appState: appState, preferences: preferences, session: appState.assistant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    // Confirmed live: at the old uniform 16pt bottom inset,
                    // this sat directly over Grades' bottom status bar,
                    // covering "Updated N minutes ago" entirely. Cleared
                    // to sit above a typical footer bar's height instead.
                    .padding(.bottom, 56)
            }
            // Fill the whole window — including the hidden title bar's strip — so
            // no grey window background shows there.
            .ignoresSafeArea()
            .background(preferences.theme.palette(for: systemScheme).canvasWash.ignoresSafeArea())
            .animation(Motion.island(reduced: reduceMotion), value: appState.isHome)
            .animation(Motion.arrival(reduced: reduceMotion), value: showingMonthOverlay)
        }
    }

    @ViewBuilder
    private func destination(for credentials: Credentials) -> some View {
        switch appState.selection {
        case .schedule:
            CalendarView(
                controller: appState.portal,
                preferences: preferences,
                calendar: appState.calendar,
                syllabus: appState.syllabus,
                credentials: credentials,
                schedule: appState.schedule,
                updaterBridge: appState.updaterBridge,
                onCheckForUpdates: { appState.updaterController.checkForUpdates(nil) },
                onEditCredentials: { appState.isEditing = true },
                settingsShowing: appState.showingSettings
            )
        case .today:
            AgendaView(
                appState: appState, preferences: preferences, calendar: appState.calendar,
                notes: appState.notes, quizzes: appState.quizzes, generation: appState.generation,
                notebook: appState.notebook
            )
        case .grades:
            GradesView(controller: appState.portal, preferences: preferences)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView(
                appState: appState,
                updaterBridge: appState.updaterBridge,
                preferences: preferences,
                calendar: appState.calendar,
                googleAuth: appState.googleAuth
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { appState.showingSettings = false }
                }
            }
        }
        // Confirmed live: with no tint set, every native control here (tab
        // selection, Done, toggles/radios) fell back to the system accent
        // instead of the room's own — a maroon app with a green Settings
        // sheet. Every other screen resolves this through \.palette; this
        // sheet needs the same color said explicitly, since native Form
        // controls read `.tint`, not the custom environment key.
        .tint(preferences.theme.palette(for: systemScheme).accent)
        // min/ideal/max instead of a fixed size — same starting size, but
        // the sheet now offers macOS's native drag-to-resize edge. Widened
        // for the sidebar (`NavigationSplitView`) the settings shell moved to.
        .frame(minWidth: 700, idealWidth: 820, maxWidth: 1000, minHeight: 480, idealHeight: 620, maxHeight: 860)
    }
}

@main
struct PUPSISPortalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView(appState: appState, preferences: appState.preferences)
        }
        // The island is the only top chrome now — no native title bar competing.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Settings by ⌘, in the app menu, now that it's a sheet not a row.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(appState.credentials == nil)
            }

            // Keep the destinations reachable from the keyboard without a sidebar.
            CommandGroup(after: .toolbar) {
                Button("Schedule") { appState.open(.schedule) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Today") { appState.open(.today) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Grades") { appState.open(.grades) }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Home") { appState.isHome = true }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                // Schedule controls now live in the island; keep their shortcuts
                // global so they work whether or not the island is hovered.
                Button("Previous") { appState.schedule.stepIntent = -1 }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(appState.selection != .schedule)
                Button("Next") { appState.schedule.stepIntent = 1 }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(appState.selection != .schedule)
                Button("New Event") { appState.schedule.newEventIntent += 1 }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(appState.selection != .schedule)
                Divider()
                // Browser-style zoom, app-wide — see uiScaled(_:) at the
                // ContentView root. ⌘0 is already "Home" above, so
                // "Actual Size" is ⌥⌘0 instead of the pure browser convention.
                Button("Zoom In") { appState.preferences.increaseUIScale() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { appState.preferences.decreaseUIScale() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { appState.preferences.resetUIScale() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }

            CommandMenu("Account") {
                Button("Refresh") { Task { await appState.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(appState.credentials == nil)

                Divider()

                Button("Edit Credentials") { appState.isEditing = true }
                Button("Sign Out") { appState.signOut() }
                    .disabled(appState.credentials == nil)
            }
        }

        // The menu bar presence: what's next at a glance, and the reason the app
        // stays useful with its window closed — the OS keeps firing the reminders
        // it already holds, and this is how you still see the schedule and reopen.
        MenuBarExtra {
            MenuBarPanel(appState: appState, preferences: appState.preferences)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }

    static let mainWindowID = "main"
}
