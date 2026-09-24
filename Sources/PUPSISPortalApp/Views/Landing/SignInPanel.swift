import SwiftUI

/// Sign in beside the portal. Same fields, checks and copy the old login
/// screen had; the student number is validated before anything is saved.
struct SignInPanel: View {
    var existing: Credentials?
    var signingIn: Bool
    var failure: String?
    /// Spec 10: the account's saved campus pick, and every code it has
    /// already taught the app, so the live line below the student number
    /// resolves without waiting on a network round trip.
    var campusOverride: Campus?
    var learnedCampusCodes: [String: String] = [:]
    let onSave: (Credentials) -> Bool
    var onPickCampus: (Campus) -> Void = { _ in }
    @Environment(\.typography) private var typography

    @State private var studentNumber: String
    @State private var birthMonth: Int
    @State private var birthDay: Int
    @State private var birthYear: Int
    @State private var password: String
    @State private var formatError = false
    @State private var keychainError = false
    @FocusState private var focusedNumber: Bool

    init(
        existing: Credentials?, signingIn: Bool, failure: String?,
        campusOverride: Campus? = nil, learnedCampusCodes: [String: String] = [:],
        onSave: @escaping (Credentials) -> Bool, onPickCampus: @escaping (Campus) -> Void = { _ in }
    ) {
        self.existing = existing
        self.signingIn = signingIn
        self.failure = failure
        self.campusOverride = campusOverride
        self.learnedCampusCodes = learnedCampusCodes
        self.onSave = onSave
        self.onPickCampus = onPickCampus
        _studentNumber = State(initialValue: existing?.studentNumber ?? "")
        _birthMonth = State(initialValue: existing?.birthMonth ?? 1)
        _birthDay = State(initialValue: existing?.birthDay ?? 1)
        _birthYear = State(initialValue: existing?.birthYear ?? 2000)
        _password = State(initialValue: existing?.password ?? "")
    }

    static func isStudentNumber(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).range(of: #"^\d{4}-\d{5}-[A-Za-z]{2}-\d{1,2}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in at the portal").font(typography.display(size: 20, weight: .semibold)).foregroundStyle(Color(rgb: 0xF4E8D6))
            Text("Use the same details as the PUP SIS.").font(typography.reading(size: 13.5)).foregroundStyle(Color(rgb: 0xA99AA3))

            field {
                TextField("2026-00000-MN-0", text: $studentNumber)
                    .textFieldStyle(.plain)
                    .font(typography.numeric(size: 14))
                    .focused($focusedNumber)
                    .accessibilityLabel("Student number")
            }
            campusLine
            HStack(spacing: 8) {
                menu($birthMonth, options: Array(1...12), label: "Birth month") { DateFormatter().shortMonthSymbols[$0 - 1] }
                menu($birthDay, options: Array(1...31), label: "Birth day") { "\($0)" }
                menu($birthYear, options: Array((1900...2016).reversed()), label: "Birth year") { "\($0)" }
            }
            field {
                SecureField("Enter your password", text: $password)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Password")
            }

            Button(action: submit) {
                Text(signingIn ? "Signing in…" : "Login now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pixelPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(signingIn || studentNumber.isEmpty || password.isEmpty)

            if formatError {
                message("Student number looks like 2026-00000-MN-0.")
            } else if keychainError {
                message("Couldn't save to Keychain.")
            } else if let failure, !signingIn {
                message(failure)
            }

            (Text("Locked in your Mac's Keychain.").bold() + Text(" This portal only ever talks to PUP SIS."))
                .font(typography.reading(size: 12))
                .foregroundStyle(Color(rgb: 0x8D7E87))
        }
        .padding(22)
        .frame(width: 360)
        .background(VoidPalette.panel, in: PixelNotch())
        .overlay(PixelNotch().strokeBorder(VoidPalette.panelLine, lineWidth: 2))
        .environment(\.colorScheme, .dark)
        .onAppear { focusedNumber = true }
    }

    private func submit() {
        guard Self.isStudentNumber(studentNumber) else { formatError = true; focusedNumber = true; return }
        formatError = false
        keychainError = !onSave(Credentials(
            studentNumber: studentNumber.trimmingCharacters(in: .whitespaces),
            birthMonth: birthMonth, birthDay: birthDay, birthYear: birthYear, password: password
        ))
    }

    private var campusResolution: CampusResolution {
        CampusCatalog.resolve(studentNumber: studentNumber, override: campusOverride, learnedCodes: learnedCampusCodes)
    }

    /// The live line under Student Number (spec 10): a found campus, an
    /// unrecognized code with a picker, or a nudge while still typing.
    @ViewBuilder
    private var campusLine: some View {
        HStack(spacing: 8) {
            switch campusResolution {
            case .known(let campus), .overridden(let campus):
                campusChip("\(campus.code ?? "") · \(campus.name)")
                Text("campus found").font(typography.reading(size: 12.5)).foregroundStyle(Color(rgb: 0xC9B9C2))
            case .unknownCode(let code):
                campusChip(code)
                Menu("Pick your campus") {
                    ForEach(CampusCatalog.all, id: \.self) { campus in
                        Button(campus.name) { onPickCampus(Campus(code: code, name: campus.name, region: campus.region)) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(typography.reading(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(rgb: 0xF0D98A))
            case .incomplete:
                Text("Your campus shows up as you type.").font(typography.reading(size: 12.5)).foregroundStyle(Color(rgb: 0xA99AA3))
            }
        }
        .frame(minHeight: 18, alignment: .leading)
    }

    private func campusChip(_ text: String) -> some View {
        Text(text)
            .font(typography.display(size: 12, weight: .semibold))
            .foregroundStyle(Color(rgb: 0xF0D98A))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(rgb: 0x2A1520), in: PixelNotch())
    }

    private func message(_ text: String) -> some View {
        Text(text).font(typography.reading(size: 13)).foregroundStyle(Color(rgb: 0xF0A090))
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(Color(rgb: 0xF1E7DD))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(rgb: 0x0B0709), in: PixelNotch())
            .overlay(PixelNotch().strokeBorder(Color(rgb: 0x3A2A33), lineWidth: 2))
    }

    private func menu<T: Hashable>(_ selection: Binding<T>, options: [T], label: String, display: @escaping (T) -> String) -> some View {
        field {
            Menu {
                ForEach(options, id: \.self) { option in Button(display(option)) { selection.wrappedValue = option } }
            } label: {
                Text(display(selection.wrappedValue)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(label)
        }
    }
}
