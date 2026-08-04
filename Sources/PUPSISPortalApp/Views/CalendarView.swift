import SwiftUI

struct CalendarView: View {
    @ObservedObject var controller: PortalController
    let credentials: Credentials

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            switch controller.status {
            case .idle, .loggingIn:
                ProgressView("Signing in…")

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("Retry") { controller.signIn(with: credentials) }
                        .tint(Theme.accent)
                }

            case .success:
                if controller.sessions.isEmpty {
                    EmptyStateView(title: "No classes found", systemImage: "calendar")
                } else {
                    WeekGrid(sessions: controller.sessions)
                }
            }
        }
        .task {
            if controller.status == .idle {
                controller.signIn(with: credentials)
            }
        }
    }
}

private struct WeekGrid: View {
    let sessions: [ClassSession]

    private let gutter: CGFloat = 56
    private let headerHeight: CGFloat = 32
    private let hourHeight: CGFloat = 56

    /// Axis padded to whole hours around the real class range, so the grid
    /// isn't a mostly-empty 24-hour column.
    private var axis: (start: Int, end: Int) {
        let starts = sessions.map(\.start)
        let ends = sessions.map(\.end)
        guard let first = starts.min(), let last = ends.max() else { return (7 * 60, 21 * 60) }
        return ((first / 60) * 60, Int(ceil(Double(last) / 60)) * 60)
    }

    private var hours: [Int] {
        stride(from: axis.start, through: axis.end, by: 60).map { $0 }
    }

    var body: some View {
        let span = CGFloat(max(axis.end - axis.start, 60))
        let bodyHeight = span / 60 * hourHeight

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter)
                ForEach(Weekday.allCases) { day in
                    Text(day.short)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: headerHeight)

            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels
                        .frame(width: gutter)

                    ZStack(alignment: .topLeading) {
                        hourLines(height: bodyHeight)

                        HStack(spacing: 4) {
                            ForEach(Weekday.allCases) { day in
                                dayColumn(day, span: span, height: bodyHeight)
                            }
                        }
                    }
                    .frame(height: bodyHeight)
                }
                .padding(.trailing, 12)
            }
        }
        .padding(16)
    }

    private var hourLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { minutes in
                Text(ClassSession.format(minutes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: hourHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.trailing, 8)
    }

    private func hourLines(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { _ in
                Rectangle()
                    .fill(Theme.gridLine)
                    .frame(height: 1)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(height: height, alignment: .top)
    }

    private func dayColumn(_ day: Weekday, span: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            ForEach(sessions.filter { $0.day == day }) { session in
                SessionBlock(session: session)
                    .frame(
                        width: proxy.size.width,
                        height: max(CGFloat(session.duration) / span * height, 24)
                    )
                    .offset(y: CGFloat(session.start - axis.start) / span * height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

private struct SessionBlock: View {
    let session: ClassSession
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.subjectCode)
                .font(.caption.bold())
            Text(session.timeLabel)
                .font(.system(size: 9))
                .opacity(0.85)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.color(for: session.subjectCode), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.white)
        .onTapGesture { showingDetail = true }
        .popover(isPresented: $showingDetail) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.subjectCode)
                    .font(.headline)
                Text(session.description)
                Text(session.timeLabel)
                    .foregroundStyle(.secondary)
                if !session.faculty.isEmpty {
                    Text(session.faculty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: 260, alignment: .leading)
        }
    }
}
