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
    let preferences = Preferences(defaults: Demo.defaults)
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
    /// so the menu commands (⌘1–6, ⌘,) can drive them, not just the view.
    @Published private(set) var selection: Destination = .today
    @Published var showingSettings = false

    /// +1 when the last navigation went down the sidebar, −1 when it went up;
    /// the screen change pushes forward or back in depth accordingly. Set in
    /// the same update as `selection`, so the transition reads it fresh.
    private(set) var navDirection = 1

    /// Bumped when a refresh finishes; the sidebar's portal glyph sends a
    /// sync ripple across the window, green on `syncOK`, red otherwise.
    @Published private(set) var syncPulse = 0
    @Published private(set) var syncOK = true
    @Published private(set) var isRefreshing = false

    /// The portal landing over the app: shown at launch, on ⌘0 (quick, frame
    /// already built) and after sign-out (full intro). The warp hides it.
    @Published var landingVisible = true
    /// True from the moment the warp starts; the app mounts under the flash
    /// then, not before, so nothing renders behind a landing that hides it.
    @Published var warpingIn = false
    @Published private(set) var landingQuick = false
    /// Bumped to restart the landing from its first beat.
    @Published private(set) var landingKey = 0

    func showHub() {
        warpingIn = false
        landingQuick = true
        landingKey += 1
        landingVisible = true
    }

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

    /// Open a destination from the sidebar, a menu command or IntAssis.
    func open(_ destination: Destination) {
        guard destination != selection else { return }
        navDirection = Destination.direction(from: selection, to: destination)
        if let tab = destination.notebookTab { notebook.tab = tab }
        selection = destination
    }

    init() {
        FontLibrary.registerBundledFonts()
        if Demo.isOn {
            #if DEBUG
            Demo.seed(self)
            #endif
        } else {
            // No-op on the lite build (no `models/` in the bundle) and on any
            // launch after the first (already adopted) — see its own doc comment.
            ModelCatalog.adoptBundledModels()
            credentials = KeychainStore.load()
            _ = updaterController // force the lazy: starts Sparkle's scheduler now, not on first UI touch
        }
        isEditing = credentials == nil
        #if DEBUG
        // A named screen is a live check: land on it, not on the hub.
        if let screen = Demo.screen { open(screen); landingVisible = false }
        #endif
        startClock()
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
                // `terminateWithoutWaiting()`, not `stop()`: this handler is
                // synchronous with no chance to `await`, and even `stop()`'s
                // bounded wait would be a visible hang on the way out —
                // firing SIGTERM is enough here, nothing relaunches after.
                LlamaServerManager.shared.terminateWithoutWaiting()
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
    /// Schedule-then-grades sequencing (and guarding a sign-out landing
    /// between the two) is `PortalController`'s own job — see `refresh()`
    /// there.
    func refresh() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            syncOK = portal.refreshError == nil
            syncPulse += 1
        }
        await portal.refresh()
        // `sync` unconditionally clears every pending reminder before
        // deciding whether to re-add any (`Notifier.reschedule`) — with
        // `authorization` still `nil` (never fetched this launch, e.g. a
        // menu-bar refresh before the window/Settings ever opened),
        // `enabled, authorization == .authorized` fails and it wipes every
        // reminder with nothing put back. Refresh first, same as
        // `CalendarView`'s own refresh already does.
        await Notifier.shared.refreshAuthorization()
        Notifier.shared.sync(portal.sessions, preferences)
    }

    /// Whether the write actually landed — pulled out of `save(_:)` as its
    /// own testable function (no `AppState` needed) so the Keychain-failure
    /// branch below doesn't require constructing a real one (heavy: Sparkle,
    /// EventKit, on-disk stores — see `testSignOutIsSynchronous`'s comment).
    static func didSave(_ credentials: Credentials, using save: (Credentials) throws -> Void = KeychainStore.save) -> Bool {
        (try? save(credentials)) != nil
    }

    /// Returns whether the credentials were actually saved. `try?` here used
    /// to swallow a Keychain write failure and sign the user in anyway with
    /// nothing persisted — a relaunch then found no credentials at all.
    /// the sign-in panel shows "Couldn't save to Keychain" and stays on the
    /// form when this comes back `false`, instead of proceeding as signed in.
    @discardableResult
    func save(_ credentials: Credentials) -> Bool {
        guard Self.didSave(credentials) else { return false }
        self.credentials = credentials
        isEditing = false
        portal.status = .idle
        return true
    }

    /// Synchronous, deliberately: every reset here has to land before this
    /// call returns, with nothing left pending after it. A fast Edit
    /// Credentials → Save → sign-in right after Sign Out must see fresh,
    /// intact credentials — not have them undone by this call still being
    /// suspended on an await when the new ones land. The one part that *is*
    /// async — clearing the SIS's cookies/local storage from the shared
    /// `WKWebsiteDataStore` — runs as its own tracked task on `portal`
    /// instead; `PortalController.runSignIn` waits for that itself before
    /// touching the web view, so the ordering is still guaranteed without
    /// this call blocking on it.
    func signOut() {
        warpingIn = false
        landingQuick = false
        landingKey += 1
        landingVisible = true
        // Must come first: an in-flight sign-in/refresh that's still running
        // must not re-save the caches deleted below after the fact.
        portal.cancelInFlight()
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
        // Forget which host we landed on — a fresh sign-in re-runs the full
        // candidate order instead of retrying whatever this account landed on.
        portal.forgetHost()
        // This account's campus pick and any code it taught the app (spec
        // 10) are this student's own, not a device-wide setting.
        preferences.clearCampus()
        // Not awaited — see the doc comment above.
        portal.beginClearingWebsiteData()
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.undoManager) private var undoManager
    /// This view sits above the `.reduceMotion(forced:)` it publishes, so it
    /// computes the same OR for its own animations.
    private var reduceMotion: Bool { systemReduceMotion || preferences.forceReducedMotion }
    @ViewBuilder private var root: some View {
        #if DEBUG
        if Demo.showsGallery { ComponentGallery() } else { content }
        #else
        content
        #endif
    }

    var body: some View {
        root
            // Reaches both branches of `content` (login screen and the main
            // app) — the login screen's own circular gear button sets this
            // same flag, so one sheet definition covers both.
            .sheet(isPresented: $appState.showingSettings) { settingsSheet }
            .frame(minWidth: 900, minHeight: 600)
            .background(TrafficLights(autoHide: preferences.trafficLightsAutoHide))
            .environment(\.palette, preferences.theme.palette(for: systemScheme))
            .environment(\.typography, Typography(preferences.fontChoice, scale: preferences.uiScale))
            .environment(\.uiScale, preferences.uiScale)
            .reduceMotion(forced: preferences.forceReducedMotion)
            // Native controls read `.tint`, not \.palette: action is the one
            // interactive hue.
            .tint(preferences.theme.palette(for: systemScheme).roles.action)
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
        ZStack {
            if let credentials = appState.credentials, !appState.isEditing, !appState.landingVisible || appState.warpingIn {
                AppShell(appState: appState, preferences: preferences, credentials: credentials)
            }
            if appState.landingVisible || appState.credentials == nil || appState.isEditing {
                PortalLanding(appState: appState, portal: appState.portal, preferences: preferences, quick: appState.landingQuick) {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.65)) { appState.landingVisible = false }
                    appState.warpingIn = false
                }
                .id(appState.landingKey)
                .transition(.opacity)
            }
        }
        // Signing in starts here, under the landing, so the SIS is already
        // loading while the student is still at the portal.
        .task(id: appState.credentials?.studentNumber) {
            if let credentials = appState.credentials, !appState.isEditing, appState.portal.status == .idle {
                appState.portal.signIn(with: credentials)
            }
        }
    }

    private var settingsSheet: some View {
        // No NavigationStack: Settings owns its full chrome itself now (a
        // hand-built top tab strip through its own slim bottom Done bar) —
        // nothing here uses push/pop, and the stack only ever existed to
        // host the `.toolbar` that lived below (now gone too, replaced by
        // SettingsView's own `bottomBar`).
        SettingsView(
            appState: appState,
            updaterBridge: appState.updaterBridge,
            preferences: preferences,
            calendar: appState.calendar,
            googleAuth: appState.googleAuth
        )
        // Confirmed live: with no tint set, every native control here (tab
        // selection, Done, toggles/radios) fell back to the system accent
        // instead of the room's own — a maroon app with a green Settings
        // sheet. Every other screen resolves this through \.palette; this
        // sheet needs the same color said explicitly, since native Form
        // controls read `.tint`, not the custom environment key.
        .tint(preferences.theme.palette(for: systemScheme).roles.action)
        // min/ideal/max instead of a fixed size — same starting size, but
        // the sheet now offers macOS's native drag-to-resize edge. Close to
        // the original (pre-sidebar) numbers, widened a bit from those:
        // confirmed live, 8 tabs (up from the original 7 — Data & Storage is
        // new) truncate their labels below ~620pt.
        .frame(minWidth: 640, idealWidth: 700, maxWidth: 820, minHeight: 480, idealHeight: 620, maxHeight: 860)
    }
}

@main
struct PUPSISPortalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView(appState: appState, preferences: appState.preferences)
        }
        // The sidebar carries the window controls; no native title bar competing.
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
                ForEach(Destination.allCases) { destination in
                    Button(destination.title) { appState.open(destination) }
                        .keyboardShortcut(destination.shortcut, modifiers: .command)
                }
                Button("Portal Hub") { appState.showHub() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(appState.credentials == nil)
                Divider()
                // Schedule's toolbar buttons, also reachable from the keyboard.
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
                // Browser-style zoom, app-wide. ⌘0 is reserved for the portal
                // hub, so "Actual Size" is ⌥⌘0.
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
                .reduceMotion(forced: appState.preferences.forceReducedMotion)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }

    static let mainWindowID = "main"
}
