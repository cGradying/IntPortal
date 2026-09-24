import SwiftUI

/// The model catalog/download section of `IntelligencePane` — one
/// `llama-server` binary, a short verified catalog of models
/// (`ModelCatalog`) — pick one, it downloads with a real progress bar, and
/// becomes the running model. The `-with-AI` dmg ships `llama-server` itself
/// inside the bundle (`LlamaServerManager.binaryCandidates` finds it there
/// first); the plain dmg still needs it once from Homebrew — the footer
/// below only says so when neither is already present.
extension IntelligencePane {
    var downloadModelsSection: some View {
        SettingsSection(
            title: "Models",
            footer: LlamaServerManager.locateBinary() == nil
                ? "Needs llama-server itself installed once — brew install llama.cpp — that one step can't be done from inside the app. (The download-with-AI build ships it already and skips this.) Every model above downloads and runs itself after that."
                : "Every model above downloads and runs itself — nothing else to install."
        ) {
            ForEach(ModelCatalog.entries) { entry in
                modelRow(entry)
            }
            if let progress = installProgress {
                ProgressView(value: progress) {
                    Text(installingLabel ?? "Downloading…").font(.caption)
                }
            }
            if let error = installError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    func modelRow(_ entry: ModelCatalog.Entry) -> some View {
        let isSelected = preferences.aiModel == entry.id
        let isDownloaded = downloadedIDs.contains(entry.id)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label).font(.callout).fontWeight(isSelected ? .semibold : .regular)
                Text(entry.description).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else if isDownloaded {
                Button("Use this model") { considerSelecting(entry) }
                    .buttonStyle(.pixelSmall).font(.caption)
            } else {
                Button("Download") { Task { await installModel(entry) } }
                    .buttonStyle(.pixelSmall).font(.caption)
                    .disabled(installProgress != nil)
            }
        }
        .padding(.vertical, 4)
    }

    /// Never writes to `preferences.aiModel` directly, so a memory check can
    /// run *before* anything is committed — Cancel then needs no revert,
    /// since nothing changed yet.
    func considerSelecting(_ entry: ModelCatalog.Entry) {
        guard entry.id != preferences.aiModel else { return }
        if let available = SystemMemory.availableBytes(),
           SystemMemory.shouldWarn(modelBytes: entry.sizeBytes, availableBytes: available) {
            pendingModelLoad = PendingModelLoad(entry: entry, availableBytes: available)
        } else {
            preferences.aiModel = entry.id
        }
    }

    /// Downloads `entry` (via the real memory-check gate above once it's on
    /// disk), plus the fixed embedding model alongside it if that isn't
    /// downloaded yet — one button covers both jobs.
    func installModel(_ entry: ModelCatalog.Entry) async {
        installError = nil
        do {
            installingLabel = "Downloading \(entry.label)…"
            installProgress = 0
            for try await fraction in ModelCatalog.download(entry) {
                installProgress = fraction
            }
            if !ModelCatalog.isDownloaded(ModelCatalog.embedModel) {
                installingLabel = "Downloading \(ModelCatalog.embedModel.label)…"
                installProgress = 0
                for try await fraction in ModelCatalog.download(ModelCatalog.embedModel) {
                    installProgress = fraction
                }
            }
            refreshDownloaded()
            considerSelecting(entry)
        } catch {
            installError = "Couldn't download \(entry.label) — \(error.localizedDescription)"
        }
        installProgress = nil
        installingLabel = nil
    }

    func refreshDownloaded() {
        downloadedIDs = Set(ModelCatalog.entries.filter(ModelCatalog.isDownloaded).map(\.id))
    }

    /// Live estimate of what `llama-server` will actually hold in RAM at the
    /// slider's current position — weights + KV cache + a flat compute-buffer
    /// overhead (`ModelCatalog.estimatedRAMBytes`). Turns red past the same
    /// 60%-of-available-RAM threshold `SystemMemory.shouldWarn` already gates
    /// the model-download confirmation with, so the two "is this too much
    /// RAM" checks in Settings agree with each other.
    var ramEstimateRow: some View {
        let entry = ModelCatalog.entry(for: preferences.aiModel) ?? ModelCatalog.entries[0]
        let estimate = ModelCatalog.estimatedRAMBytes(
            for: entry, contextSize: preferences.aiContextSize, quantizedKVCache: preferences.aiKVCacheQuantized
        )
        let estimateGB = Double(estimate) / 1_073_741_824
        let tooMuch = SystemMemory.availableBytes().map {
            SystemMemory.shouldWarn(modelBytes: estimate, availableBytes: $0)
        } ?? false
        return HStack(spacing: 4) {
            Image(systemName: tooMuch ? "exclamationmark.triangle.fill" : "memorychip")
            Text(String(format: "~%.1f GB RAM at this context size", estimateGB))
        }
        .font(.caption2)
        .foregroundStyle(tooMuch ? .red : .secondary)
    }
}

/// A model whose size crossed the memory-check threshold, held for
/// confirmation before it's ever written to `preferences.aiModel`.
struct PendingModelLoad: Identifiable {
    let entry: ModelCatalog.Entry
    let availableBytes: UInt64
    var id: String { entry.id }

    var message: String {
        let modelGB = Double(entry.sizeBytes) / 1_073_741_824
        let availableGB = Double(availableBytes) / 1_073_741_824
        return String(format: "This model needs about %.1f GB. You have about %.1f GB available.", modelGB, availableGB)
    }
}
