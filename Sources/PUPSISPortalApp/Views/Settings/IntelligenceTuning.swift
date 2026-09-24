import SwiftUI

/// The advanced generation/runtime knobs and the RAG tuning knobs — the rest
/// of `IntelligencePane`, split out purely to stay under the line budget.
extension IntelligencePane {
    /// Knobs the app already had fixed constants for — sampling temperature,
    /// the reply token budget, KV cache quantization, GPU offload — surfaced
    /// as real controls instead of staying hardcoded. Gated on `aiEnabled`
    /// like the rest of the pane; footers stay on screen, not behind a "?".
    var advancedAITuningSection: some View {
        SettingsSection(
            title: "Advanced AI Tuning",
            footer: """
            Temperature: lower is more focused and repeatable, higher is more varied. \
            Output token budget: the ceiling on a single reply — raising it without \
            enough context headroom can make a turn refuse to run rather than truncate. \
            Quantizing the KV cache roughly halves its RAM cost per token of context; \
            turning it off approximates the older, more precise fp16 cache. GPU off \
            forces CPU-only, mainly useful for isolating a slowdown or crash. All four \
            restart the local model process when changed, and only affect the \
            llama-server-backed (Intel) chat model — the Apple Silicon MLX runtime \
            manages its own KV cache and always uses the GPU.
            """
        ) {
            if preferences.aiEnabled {
                SettingsRow(label: "Response temperature") {
                    Text(String(format: "%.2f", preferences.aiTemperature)).foregroundStyle(.secondary)
                }
                Slider(value: $preferences.aiTemperature, in: 0...1, step: 0.05)
                SettingsRow(label: "Output token budget") {
                    Text("\(preferences.aiOutputTokenBudget) tokens").foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(preferences.aiOutputTokenBudget) },
                        set: { preferences.aiOutputTokenBudget = Int($0) }
                    ),
                    in: Double(Preferences.aiOutputTokenBudgetRange.lowerBound)...Double(Preferences.aiOutputTokenBudgetRange.upperBound),
                    step: 128
                )
                SettingsRow(label: "Quantize KV cache (q8_0)") {
                    Toggle("", isOn: $preferences.aiKVCacheQuantized).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Use GPU (Metal)") {
                    Toggle("", isOn: $preferences.aiUseGPU).labelsHidden().toggleStyle(.switch)
                }
                Button("Reset to Defaults") {
                    preferences.aiTemperature = Preferences.aiDefaultTemperature
                    preferences.aiOutputTokenBudget = Preferences.aiDefaultOutputTokenBudget
                    preferences.aiKVCacheQuantized = true
                    preferences.aiUseGPU = true
                }
                .buttonStyle(.pixelSmall)
                .font(.caption)
            } else {
                Text("Turn on IntAssis above to tune these.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// How the assistant searches notes — chunk size, similarity floor,
    /// context budget, answer temperature.
    var ragTuningSection: some View {
        SettingsSection(
            title: "AI Tuning",
            footer: """
            How the assistant searches your notes (the AI's own search, and /rag). Chunk size is how much \
            text is grouped per match; similarity floor is how loose a match counts as relevant — lower finds \
            more, at the risk of an unrelated note slipping in. Context budget caps how much matched text \
            reaches the answer model.
            """
        ) {
            SettingsRow(label: "Chunk size") {
                Text("\(preferences.ragChunkSize) chars").foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.ragChunkSize) },
                    set: { preferences.ragChunkSize = Int($0) }
                ),
                in: 200...2000,
                step: 100
            )
            SettingsRow(label: "Similarity floor") {
                Text(String(format: "%.2f", preferences.ragSimilarityFloor)).foregroundStyle(.secondary)
            }
            Slider(value: $preferences.ragSimilarityFloor, in: 0...1, step: 0.05)
            SettingsRow(label: "Context budget") {
                Text("\(preferences.ragContextBudget) chars").foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.ragContextBudget) },
                    set: { preferences.ragContextBudget = Int($0) }
                ),
                in: 1000...20000,
                step: 500
            )
            SettingsRow(label: "Answer temperature") {
                Text(String(format: "%.2f", preferences.ragAnswerTemperature)).foregroundStyle(.secondary)
            }
            Slider(value: $preferences.ragAnswerTemperature, in: 0...1, step: 0.05)
            Button("Reset to Defaults") {
                preferences.ragChunkSize = Preferences.ragDefaultChunkSize
                preferences.ragSimilarityFloor = Preferences.ragDefaultSimilarityFloor
                preferences.ragContextBudget = Preferences.ragDefaultContextBudget
                preferences.ragAnswerTemperature = Preferences.ragDefaultAnswerTemperature
            }
            .buttonStyle(.pixelSmall)
            .font(.caption)
        }
    }
}
