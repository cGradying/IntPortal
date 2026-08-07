import SwiftUI

struct CredentialsView: View {
    var existing: Credentials?
    var onSave: (Credentials) -> Void
    @Environment(\.palette) private var palette

    @State private var studentNumber: String
    @State private var birthMonth: Int
    @State private var birthDay: Int
    @State private var birthYear: Int
    @State private var password: String

    private let months = Array(1...12)
    private let days = Array(1...31)
    private let years = Array((1900...2016).reversed())

    init(existing: Credentials?, onSave: @escaping (Credentials) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _studentNumber = State(initialValue: existing?.studentNumber ?? "")
        _birthMonth = State(initialValue: existing?.birthMonth ?? 1)
        _birthDay = State(initialValue: existing?.birthDay ?? 1)
        _birthYear = State(initialValue: existing?.birthYear ?? 2000)
        _password = State(initialValue: existing?.password ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PUP SIS Login")
                .font(Theme.Typo.screenTitle)
                .foregroundStyle(palette.accent)

            TextField("Student Number (e.g. 2020-00000-MN-0)", text: $studentNumber)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Month", selection: $birthMonth) {
                    ForEach(months, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Day", selection: $birthDay) {
                    ForEach(days, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Year", selection: $birthYear) {
                    ForEach(years, id: \.self) { Text("\($0)").tag($0) }
                }
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button("Save") {
                onSave(Credentials(
                    studentNumber: studentNumber,
                    birthMonth: birthMonth,
                    birthDay: birthDay,
                    birthYear: birthYear,
                    password: password
                ))
            }
            .keyboardShortcut(.defaultAction)
            .tint(palette.accent)
            .disabled(studentNumber.isEmpty || password.isEmpty)
        }
        .padding(24)
        .frame(width: 360)
        // A form is chrome, not content, so glass is the right layer for it.
        .glassPanel(cornerRadius: 20)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvasWash.ignoresSafeArea())
    }
}
