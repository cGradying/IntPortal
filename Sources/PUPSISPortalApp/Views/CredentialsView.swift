import SwiftUI

/// The login screen — the one place `AppState.credentials == nil` shows
/// anything at all (`ContentView`'s gate). Split-screen: a dark hero side
/// carrying the wordmark and welcome line, a glass form card on the other.
/// Every color comes from `palette` — the layout is fixed, the theme is not.
///
/// ponytail: no spinner or auth-failure state lives here. Saving flips
/// `isEditing = false`, which swaps to `CalendarView` — its `.task` fires the
/// sign-in and its `startupState` already renders "Signing in…" and the
/// failure screen with retry. A second copy of that here would just be a
/// second source of truth for the same `LoginStatus`.
struct CredentialsView: View {
    var existing: Credentials?
    var onSave: (Credentials) -> Void
    /// The only pre-login navigation affordance — no nav island exists yet,
    /// deliberately: this circular button is the one door in.
    @Binding var showingSettings: Bool
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var studentNumber: String
    @State private var birthMonth: Int
    @State private var birthDay: Int
    @State private var birthYear: Int
    @State private var password: String
    @State private var arrived = false

    private let months = Array(1...12)
    private let days = Array(1...31)
    private let years = Array((1900...2016).reversed())

    init(existing: Credentials?, onSave: @escaping (Credentials) -> Void, showingSettings: Binding<Bool>) {
        self.existing = existing
        self.onSave = onSave
        self._showingSettings = showingSettings
        _studentNumber = State(initialValue: existing?.studentNumber ?? "")
        _birthMonth = State(initialValue: existing?.birthMonth ?? 1)
        _birthDay = State(initialValue: existing?.birthDay ?? 1)
        _birthYear = State(initialValue: existing?.birthYear ?? 2000)
        _password = State(initialValue: existing?.password ?? "")
    }

    var body: some View {
        HStack(spacing: 0) {
            hero
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            form
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            settingsButton
                .padding(20)
        }
        .opacity(arrived ? 1 : 0)
        .animation(Motion.arrival(reduced: reduceMotion), value: arrived)
        .task { arrived = true }
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .glassInteractive(in: Circle())
        .help("Settings")
    }

    // MARK: Hero side

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            palette.panel
            HomeNoiseField(color: palette.accent)

            Ellipse()
                .fill(palette.secondary)
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 90, y: 90)

            VStack(alignment: .leading, spacing: 24) {
                Text("PUPSIS IntPortal")
                    .font(typography.footer.weight(.bold))
                    .tracking(2.8)
                    .foregroundStyle(palette.onPanel)

                Spacer()

                GlitchGradientText(
                    text: "Welcome.\nStart your study session now with Int Portal!",
                    font: typography.loginHeadline,
                    gradient: [palette.accent, palette.secondary]
                )
                .italic()
                .lineSpacing(8)
            }
            .padding(48)
        }
        .clipped()
    }

    // MARK: Form side

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Login to your PUP SIS account")
                .font(typography.screenTitle)
                .foregroundStyle(.primary)

            labeledField("Student Number") {
                TextField("2000-00000-MN-00", text: $studentNumber)
                    .textFieldStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Date of birth")
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    dropdown($birthMonth, options: months, display: monthName)
                    dropdown($birthDay, options: days, display: { "\($0)" })
                    dropdown($birthYear, options: years, display: { "\($0)" })
                }
            }

            labeledField("Password") {
                SecureField("Enter your password", text: $password)
                    .textFieldStyle(.plain)
            }

            // The single highest-stakes moment in the app — a real SIS
            // password — said nothing about where it goes. The fuller
            // version of this already exists in Settings › About, filed
            // where nobody sees it at the moment it would matter.
            Text("Locked in your Mac's Keychain. This portal only ever talks to PUP SIS.")
                .font(typography.footer)
                .foregroundStyle(.secondary)

            Button {
                onSave(Credentials(
                    studentNumber: studentNumber,
                    birthMonth: birthMonth,
                    birthDay: birthDay,
                    birthYear: birthYear,
                    password: password
                ))
            } label: {
                Text("Login now")
                    .font(typography.footer.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .keyboardShortcut(.defaultAction)
            .glassProminentButton()
            .tint(palette.accent)
            .disabled(studentNumber.isEmpty || password.isEmpty)
        }
        .padding(48)
        .frame(maxHeight: .infinity, alignment: .center)
        .background(palette.canvasWash)
        .glassPanel(in: Rectangle())
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(typography.footer)
                .foregroundStyle(.secondary)
            fieldBox(content: content)
        }
    }

    /// A `Menu`, not a `Picker` — `.menuStyle(.borderlessButton)` drops the
    /// native `NSPopUpButton` bezel entirely, leaving only `fieldBox`'s own
    /// stroke. A plain `Picker(.menu)` draws its bezel regardless of styling,
    /// which is the gray box this replaces.
    private func dropdown<T: Hashable>(
        _ selection: Binding<T>, options: [T], display: @escaping (T) -> String
    ) -> some View {
        fieldBox {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(display(option)) { selection.wrappedValue = option }
                }
            } label: {
                Text(display(selection.wrappedValue))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            // `.borderlessButton` still draws its own disclosure arrow on top
            // of whatever the label provides — hide it, this field's clean
            // stroke is the only affordance it needs.
            .menuIndicator(.hidden)
        }
    }

    private func fieldBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(palette.gridLine, lineWidth: 1.5)
            )
    }

    private func monthName(_ month: Int) -> String {
        DateFormatter().shortMonthSymbols[month - 1]
    }
}
