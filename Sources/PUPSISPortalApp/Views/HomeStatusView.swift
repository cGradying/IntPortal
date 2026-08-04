import SwiftUI

struct HomeStatusView: View {
    @ObservedObject var controller: PortalController
    let credentials: Credentials

    var body: some View {
        VStack(spacing: 16) {
            switch controller.status {
            case .idle:
                ProgressView()

            case .loggingIn:
                ProgressView("Signing in…")

            case .success:
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text(credentials.studentNumber)
                    .foregroundStyle(.secondary)
                Button("Refresh Schedule & Grades") {
                    Task { await controller.refreshData() }
                }
                .tint(Theme.accent)

            case .failed(let message):
                Label("Sign-in failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Retry") {
                    controller.signIn(with: credentials)
                }
                .tint(Theme.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
