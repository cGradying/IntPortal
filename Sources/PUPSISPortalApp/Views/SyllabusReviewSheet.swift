import SwiftUI

/// Extracted syllabus items land here before anything is saved — same gate
/// `CardReviewSheet` puts in front of generated flashcards: edit or drop a
/// bad item, then Add. Nothing writes to `SyllabusStore` until this commits.
struct SyllabusReviewSheet: View {
    @State private var items: [SyllabusItem]
    @State private var gradingComponents: [GradingComponent]
    let failedChunks: Int
    let totalChunks: Int
    /// True when the source material had more chunks than
    /// `SyllabusExtractor.maxChunksPerRun` and the rest was left unused.
    let truncatedMaterial: Bool
    let onSave: ([SyllabusItem], [GradingComponent]) -> Void
    let onBack: () -> Void

    init(
        items: [SyllabusItem], gradingComponents: [GradingComponent] = [],
        failedChunks: Int, totalChunks: Int, truncatedMaterial: Bool = false,
        onSave: @escaping ([SyllabusItem], [GradingComponent]) -> Void, onBack: @escaping () -> Void
    ) {
        _items = State(initialValue: items)
        _gradingComponents = State(initialValue: gradingComponents)
        self.failedChunks = failedChunks
        self.totalChunks = totalChunks
        self.truncatedMaterial = truncatedMaterial
        self.onSave = onSave
        self.onBack = onBack
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if truncatedMaterial {
                banner("Your material was longer than one extraction run covers — only the first part was used.")
            }
            if failedChunks > 0 {
                banner("\(failedChunks) of \(totalChunks) chunk(s) failed to extract — the \(items.count) item(s) below are from the rest.")
            }
            if let generated = items.first, generated.source == .generated {
                banner("Generated study guide — not the real course syllabus. Check it against what your professor actually assigned.")
            }
            List {
                if !gradingComponents.isEmpty {
                    Section("Grading breakdown") {
                        ForEach($gradingComponents) { $component in
                            componentRow($component)
                        }
                    }
                }
                Section {
                    ForEach($items) { $item in
                        itemRow($item)
                    }
                }
            }
            .listStyle(.plain)
            HStack {
                Button("Back") { onBack() }
                Spacer()
                Text("\(items.count) item(s)").foregroundStyle(.secondary)
                Spacer()
                Button("Add") { onSave(items, gradingComponents) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(items.isEmpty)
            }
            .padding(12)
        }
    }

    private func componentRow(_ component: Binding<GradingComponent>) -> some View {
        HStack {
            TextField("Component", text: component.name)
            Spacer()
            TextField("Weight", value: component.weight, format: .number)
                .frame(width: 50)
                .multilineTextAlignment(.trailing)
            Text("%").foregroundStyle(.secondary)
            Button(role: .destructive) {
                gradingComponents.removeAll { $0.id == component.wrappedValue.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1))
    }

    private func itemRow(_ item: Binding<SyllabusItem>) -> some View {
        SyllabusReviewRow(item: item, dateFormatter: Self.dateFormatter) {
            items.removeAll { $0.id == item.wrappedValue.id }
        }
    }
}

private struct SyllabusReviewRow: View {
    @Binding var item: SyllabusItem
    let dateFormatter: DateFormatter
    let onDelete: () -> Void

    @State private var hasDate: Bool

    init(item: Binding<SyllabusItem>, dateFormatter: DateFormatter, onDelete: @escaping () -> Void) {
        _item = item
        self.dateFormatter = dateFormatter
        self.onDelete = onDelete
        _hasDate = State(initialValue: item.wrappedValue.date != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Topic", text: $item.topic, axis: .vertical)
                .font(.body.weight(.medium))
            HStack {
                Stepper(value: weekBinding, in: 0...52) {
                    Text(item.week.map { "Week \($0)" } ?? "No week")
                }
                .fixedSize()
                Picker("Type", selection: $item.type) {
                    ForEach(SyllabusItemType.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
                Spacer()
                Toggle("Date", isOn: $hasDate)
                    .toggleStyle(.checkbox)
                    .onChange(of: hasDate) { _, newValue in
                        item.date = newValue ? (item.date ?? Date()) : nil
                    }
                if hasDate {
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .fixedSize()
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    /// `Stepper`'s `value` needs a non-optional binding — 0 reads as "no
    /// week" (`SyllabusItem.week` stays nil), matching the empty-state text.
    private var weekBinding: Binding<Int> {
        Binding(
            get: { item.week ?? 0 },
            set: { item.week = $0 == 0 ? nil : $0 }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { item.date ?? Date() }, set: { item.date = $0 })
    }
}
