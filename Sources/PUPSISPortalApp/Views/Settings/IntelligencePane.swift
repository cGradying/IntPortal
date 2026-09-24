import SwiftUI

/// IntAssis, its models, the RAG tuning knobs, and the advanced
/// generation/runtime knobs — everything AI-related in one place. Split
/// across three files (this one, `IntelligenceModels.swift`,
/// `IntelligenceTuning.swift`) purely to stay under the 350-line pane
/// budget; it's one view, its state lives here, the other two files are
/// `extension IntelligencePane` adding sections that read/write it.
struct IntelligencePane: View {
    @ObservedObject var preferences: Preferences

    /// A local buffer for the selected provider's API key (wayfinder ticket
    /// #17) — deliberately not a `Preferences` field; it's loaded from/saved
    /// straight to `AIProviderKeyStore` (Keychain), never `UserDefaults`.
    @State var apiKeyDraft = ""
    /// Whether the context-size explainer popover is showing.
    @State var showingContextInfo = false
    /// Held here rather than acted on immediately when a pick would need more
    /// memory than looks available — `.alert(item:)` asks first.
    @State var pendingModelLoad: PendingModelLoad?
    /// `nil` when no download is running; 0...1 while `installModel` pulls.
    @State var installProgress: Double?
    @State var installingLabel: String?
    @State var installError: String?
    /// Recomputed after every download — which `ModelCatalog` entries are
    /// actually on disk, driving each row's Download/Selected state.
    @State var downloadedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            aiSection
            downloadModelsSection
            advancedAITuningSection
            ragTuningSection
            SettingsTechnicalSection(rows: [
                ("llama-server binary", LlamaServerManager.locateBinary() ?? "not found"),
                ("Selected model path", ModelCatalog.entry(for: preferences.aiModel)
                    .map { ModelCatalog.localURL(for: $0).path } ?? "—"),
                ("Chat port", LlamaServerManager.shared.endpoint(for: .chat)?.port.map(String.init) ?? "not running (assigned per launch)"),
                ("Embed port", LlamaServerManager.shared.endpoint(for: .embed)?.port.map(String.init) ?? "not running (assigned per launch)"),
            ])
        }
    }

    /// Beta, off by default. Lives on this pane alongside the local-model
    /// download steps and the RAG tuning knobs.
    var aiSection: some View {
        SettingsSection(
            title: "AI (beta)",
            footer: """
            IntAssis: a floating assistant (bottom-left, when this is on) \
            that can read and add to your notes, read and add calendar \
            events, and read your grades — never delete, move, or change \
            one. Local is the default — pick a model below and everything \
            downloads and runs itself, no separate app needed, nothing \
            leaves this Mac.

            A cloud provider (OpenAI/Google/Anthropic) is opt-in: pick one \
            under Model source and paste in your own API key. That key and \
            your prompts go straight to the provider's own API — this \
            app's local model, and RAG note search, are untouched either way.

            It can be wrong, local or cloud. Treat anything it tells you \
            — a summary, a date, an answer from your notes — as a draft to \
            check, not a fact.
            """
        ) {
            SettingsRow(label: "IntAssis") {
                Toggle("", isOn: $preferences.aiEnabled).labelsHidden().toggleStyle(.switch)
            }
            if preferences.aiEnabled {
                SettingsRow(label: "Model source") {
                    Picker("", selection: $preferences.aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160, alignment: .trailing)
                }
                if preferences.aiProvider.needsAPIKey {
                    SettingsRow(label: "Model") {
                        TextField("", text: $preferences.aiProviderModel, prompt: Text(preferences.aiProvider.defaultModel))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200, alignment: .trailing)
                    }
                    SettingsRow(label: "API key") {
                        SecureField("", text: $apiKeyDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200, alignment: .trailing)
                            .onChange(of: apiKeyDraft) { _, newValue in
                                if newValue.isEmpty {
                                    AIProviderKeyStore.delete(for: preferences.aiProvider)
                                } else {
                                    try? AIProviderKeyStore.save(newValue, for: preferences.aiProvider)
                                }
                            }
                    }
                    // Spec 07 point 5: names what still runs locally either way.
                    Text("Stored in your Keychain, sent only to \(preferences.aiProvider.label)'s own API. Note search and quiz generation still run on this Mac.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                SettingsRow(label: "Permission") {
                    Picker("", selection: $preferences.aiPermission) {
                        ForEach(AssistantPermission.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                }
                Text(preferences.aiPermission.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                SettingsRow(label: "Text reveal") {
                    Picker("", selection: $preferences.aiRevealAnimation) {
                        ForEach(AIRevealAnimation.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160, alignment: .trailing)
                }
                Button("Edit IntAssis instructions…") {
                    NSWorkspace.shared.open(AssistantInstructions.ensureExists())
                }
                .buttonStyle(.pixelSmall)
                .font(.caption)
                SettingsRow(label: "Thinking") {
                    Picker("", selection: $preferences.aiThinking) {
                        ForEach(AssistantThinking.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140, alignment: .trailing)
                }
                Text(preferences.aiThinking.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    SettingsRow(label: "Context size") {
                        Text("\(preferences.aiContextSize) tokens").foregroundStyle(.secondary)
                    }
                    Button { showingContextInfo = true } label: {
                        Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("What does raising this do?")
                    .popover(isPresented: $showingContextInfo, arrowEdge: .bottom) { contextSizeInfoPopover }
                }
                Slider(
                    value: Binding(
                        get: { Double(preferences.aiContextSize) },
                        set: { preferences.aiContextSize = Int($0) }
                    ),
                    in: Double(Preferences.aiContextSizeRange.lowerBound)...Double(Preferences.aiContextSizeRange.upperBound),
                    step: 512
                )
                ramEstimateRow
                Text("How much conversation, notes, and tool results the model can hold at once. Restarts the local model process when changed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: preferences.aiEnabled) {
            if preferences.aiEnabled {
                refreshDownloaded()
            } else {
                // Not just "don't load more" — actually free what's running,
                // so turning the assistant off is also turning it off.
                await LlamaServerManager.shared.stop()
            }
        }
        .task(id: preferences.aiProvider) {
            apiKeyDraft = AIProviderKeyStore.load(for: preferences.aiProvider) ?? ""
        }
        .alert(item: $pendingModelLoad) { pending in
            Alert(
                title: Text("Switch to \(pending.entry.label)?"),
                message: Text(pending.message),
                primaryButton: .default(Text("Load Anyway")) { preferences.aiModel = pending.entry.id },
                secondaryButton: .cancel()
            )
        }
    }

    /// Same "?" popover language as the assistant's own capabilities/thinking
    /// buttons — this app's one pattern for "explain the knob before you turn it."
    var contextSizeInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context size").font(.headline)
            Text("""
            How many tokens (roughly ¾ of a word each) the model can hold at once — \
            your message, the conversation so far, any pinned note, and whatever it \
            retrieved for `/rag`, all combined. Qwen3-1.7B supports up to 32,768.
            """)
            VStack(alignment: .leading, spacing: 4) {
                Text("Higher").fontWeight(.semibold)
                Text("• Longer conversations before old messages get dropped")
                Text("• More room for pinned notes and RAG results, less truncation")
                Text("• Longer tool-call chains stay coherent")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Higher costs").fontWeight(.semibold)
                Text("• Far more RAM — the KV cache grows with context size, so 32k can need several GB more than 4k")
                Text("• Slower first reply — processing a long prompt takes longer before the model starts answering")
                Text("• Slower once the conversation is long — attention cost grows with how full the context is")
                Text("• On a Mac tight on RAM, llama-server can fail to start or get killed by the OS")
            }
            Text("Changing this restarts the local model process. Lower it back down if replies get sluggish or it stops starting.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding()
        .frame(width: 320)
    }
}
