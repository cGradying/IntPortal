import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case schedule = "Schedule"
    case grades = "Grades"
    case enrollment = "Enrollment"
    case accounts = "Accounts"
    case forms = "Forms"
    case hdf = "HDF"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .schedule: "calendar"
        case .grades: "chart.bar"
        case .enrollment: "person.text.rectangle"
        case .accounts: "creditcard"
        case .forms: "doc.text"
        case .hdf: "folder"
        }
    }

    /// SIS path for sections that fall back to the raw embedded page.
    var rawPath: String? {
        switch self {
        case .home, .schedule, .grades: nil
        case .enrollment: "enrollment"
        case .accounts: "accounts"
        case .forms: "forms"
        case .hdf: "hdf"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var controller: PortalController
    let credentials: Credentials

    @State private var selection: DashboardSection? = .home

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("PUPSISPortal")
        } detail: {
            detail(for: selection ?? .home)
        }
        .tint(Theme.accent)
        .task {
            if controller.status == .idle {
                controller.signIn(with: credentials)
            }
        }
    }

    @ViewBuilder
    private func detail(for section: DashboardSection) -> some View {
        switch section {
        case .home:
            HomeStatusView(controller: controller, credentials: credentials)
        case .schedule:
            ScheduleView(entries: controller.schedule)
        case .grades:
            GradesView(entries: controller.grades, summary: controller.summary)
        default:
            if let path = section.rawPath {
                PortalWebView(webView: controller.webView)
                    .onAppear { controller.openRawPage(path: path) }
            }
        }
    }
}
