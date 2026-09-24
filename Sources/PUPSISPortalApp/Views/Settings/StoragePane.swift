import AppKit
import SwiftUI

/// Every file this app writes to disk, with its real (cached) size and a way
/// to get to it or clear it. Every location it reads is a static file/
/// directory URL, so this pane needs nothing beyond `preferences`.
struct StoragePane: View {
    @ObservedObject var preferences: Preferences

    @Environment(\.reduceMotion) private var reduceMotion
    /// Computed off the render path — see `refreshDiskUsage()`. A synchronous
    /// recursive `FileManager` walk on every body evaluation was a real,
    /// measurable lag source.
    @State private var fileSizes: [String: Int64] = [:]
    @State private var modelSizes: [String: Int64] = [:]

    /// The 4 fixed (label, url) pairs `refreshDiskUsage()` and `body` both need.
    private var dataStorageFiles: [(label: String, url: URL)] {
        [
            ("Schedule cache", ScheduleStore.fileURL),
            ("Notes & vault", NotesStore.defaultURL),
            ("Syllabus", SyllabusStore.defaultURL),
            ("Quiz decks", QuizStore.defaultRoot),
        ]
    }

    var body: some View {
        let downloadedModels = (ModelCatalog.entries + [ModelCatalog.embedModel]).filter(ModelCatalog.isDownloaded)
        let modelsTotal = downloadedModels.reduce(Int64(0)) { $0 + (modelSizes[$1.id] ?? 0) }
        let filesTotal = dataStorageFiles.reduce(Int64(0)) { $0 + (fileSizes[$1.label] ?? 0) }

        return VStack(alignment: .leading, spacing: 20) {
            SettingsSection(
                title: "Files",
                footer: "Everything this app stores — schedule, notes, syllabus, quiz decks. Reveal opens Finder with the file (or folder) selected; nothing here is deleted from this list."
            ) {
                SettingsRow(label: "Total on disk") {
                    Text(byteCountFormatter.string(fromByteCount: filesTotal + modelsTotal))
                        .fontWeight(.semibold)
                }
                ForEach(dataStorageFiles, id: \.label) { file in
                    SettingsRow(label: file.label) {
                        HStack(spacing: 8) {
                            Text(byteCountFormatter.string(fromByteCount: fileSizes[file.label] ?? 0))
                                .foregroundStyle(.secondary)
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                            .buttonStyle(.pixelSmall).font(.caption)
                        }
                    }
                }
            }

            SettingsSection(
                title: "AI Models",
                footer: "Deleting the model currently selected in Intelligence is disabled — switch models first. Deleting frees disk space immediately; re-downloading is the only way back."
            ) {
                if downloadedModels.isEmpty {
                    Text("No models downloaded yet — see Intelligence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(downloadedModels) { entry in
                        SettingsRow(label: entry.label) {
                            HStack(spacing: 8) {
                                Text(byteCountFormatter.string(fromByteCount: modelSizes[entry.id] ?? 0))
                                    .foregroundStyle(.secondary)
                                Button("Delete", role: .destructive) {
                                    withAnimation(Motion.selection(reduced: reduceMotion)) {
                                        try? FileManager.default.removeItem(at: ModelCatalog.localURL(for: entry))
                                    }
                                    refreshDiskUsage()
                                }
                                .buttonStyle(.borderless).controlSize(.small).font(.caption)
                                .disabled(entry.id == preferences.aiModel)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .task { refreshDiskUsage() }
    }

    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// A file's size, or a directory's recursive total — `NotesStore`'s
    /// vault and a downloaded `.mlx` model are both directories; a shallow
    /// `enumerator` sum treats either the same as a single file's
    /// `attributesOfItem`. Missing paths (nothing downloaded/written yet)
    /// read as zero rather than erroring. Pure — safe to call off the main
    /// actor from `refreshDiskUsage()`'s detached task.
    nonisolated private func fileSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let attributes = try? fm.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Computes every file/model size off the render path, on a detached
    /// background task instead of running synchronously in the view body on
    /// every SwiftUI re-evaluation. Called once when this pane appears, and
    /// again right after a model delete.
    private func refreshDiskUsage() {
        let files = dataStorageFiles
        let models = (ModelCatalog.entries + [ModelCatalog.embedModel]).filter(ModelCatalog.isDownloaded)
        Task.detached(priority: .utility) { [self] in
            var newFileSizes: [String: Int64] = [:]
            for file in files { newFileSizes[file.label] = fileSize(at: file.url) }
            var newModelSizes: [String: Int64] = [:]
            for entry in models { newModelSizes[entry.id] = fileSize(at: ModelCatalog.localURL(for: entry)) }
            let finalFileSizes = newFileSizes
            let finalModelSizes = newModelSizes
            await MainActor.run {
                fileSizes = finalFileSizes
                modelSizes = finalModelSizes
            }
        }
    }
}
