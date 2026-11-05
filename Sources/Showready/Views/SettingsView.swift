#if os(macOS)
import SwiftUI
import ShowreadyCore

struct SettingsView: View {
    var body: some View {
        TabView {
            APIKeySettings().tabItem { Label("API Key", systemImage: "key") }
            ModelPriceSettings().tabItem { Label("Models & Prices", systemImage: "dollarsign.circle") }
            OutputSettings().tabItem { Label("Output", systemImage: "square.and.arrow.up") }
            SpendSettings().tabItem { Label("Spending", systemImage: "chart.bar") }
            UpdateSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 720, height: 480)
    }
}

struct UpdateSettings: View {
    @EnvironmentObject var updates: UpdateController
    @State private var automatic = UpdatePreference.automatic
    @State private var frequency = UpdatePreference.frequency

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version", value: updates.currentVersion)
                Toggle("Check for updates automatically", isOn: $automatic)
                    .onChange(of: automatic) { _, v in UpdatePreference.automatic = v }
                Picker("Check", selection: $frequency) {
                    ForEach(UpdateFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: frequency) { _, v in UpdatePreference.frequency = v }
                .disabled(!automatic)
            }
            Section {
                HStack {
                    Button("Check Now") { updates.checkNow() }.disabled(updates.checking)
                    if updates.checking { ProgressView().controlSize(.small) }
                    Text(updates.status).foregroundStyle(.secondary)
                    Spacer()
                    if let update = updates.availableUpdate {
                        Button("Install \(update.version.description)…") { updates.offer(update) }
                            .buttonStyle(.borderedProminent)
                            .disabled(updates.isInstalling)
                    }
                }
            } footer: {
                Text("Updates come from GitHub releases. Before installing, the download is verified: the signature must be this developer's and Apple must have notarised the exact build.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct APIKeySettings: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @State private var status = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                SecureField("OpenAI API key (sk-…)", text: $draft)
                HStack {
                    Button("Save") {
                        draft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.apiKey = draft
                        status = draft.isEmpty ? "Key removed." : "Saved to Keychain."
                    }
                    Button("Test key") { Task { await test() } }.disabled(draft.isEmpty || testing)
                    if testing { ProgressView().controlSize(.small) }
                    Text(status).foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create a key at platform.openai.com → API keys. The key is stored in your macOS Keychain and only sent to api.openai.com.")
                    Text("GPT Image models may require Organization Verification in the OpenAI console. A 403 error usually means that step is missing.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = store.apiKey }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            try await OpenAIImageClient(apiKey: draft.trimmingCharacters(in: .whitespacesAndNewlines)).testKey()
            status = "Key works."
        } catch {
            status = error.localizedDescription
        }
    }
}

struct ModelPriceSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var newID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prices are USD per 1 million tokens. OpenAI changes them, so check openai.com/api/pricing and edit here.")
                .font(.caption).foregroundStyle(.secondary)
            Table(store.models) {
                TableColumn("Model ID") { (m: ImageModel) in Text(m.id).textSelection(.enabled) }
                    .width(min: 160, ideal: 190)
                TableColumn("Text in") { (m: ImageModel) in priceField(price(m.id, \.textInputPerM)) }
                TableColumn("Image in") { (m: ImageModel) in priceField(price(m.id, \.imageInputPerM)) }
                TableColumn("Image out") { (m: ImageModel) in priceField(price(m.id, \.imageOutputPerM)) }
                TableColumn("Sizes") { (m: ImageModel) in Text(m.sizeMode == .custom ? "Up to 3840" : "1536 max") }
            }
            HStack {
                TextField("Add model ID (e.g. a new gpt-image release)", text: $newID)
                Button("Add") {
                    let id = newID.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, !store.models.contains(where: { $0.id == id }) else { return }
                    store.models.append(ImageModel(id: id, displayName: id, textInputPerM: 5, imageInputPerM: 8,
                                                   imageOutputPerM: 30, sizeMode: .custom,
                                                   qualities: [.low, .medium, .high]))
                    newID = ""
                }
                Spacer()
                Button("Reset to defaults") { store.models = ModelCatalog.defaults }
                Button("Reset cost learning") { store.calibration = Calibration() }
                    .help("Estimates learn from your real usage. Reset if prices changed.")
            }
        }
        .padding()
    }

    private func price(_ id: String, _ kp: WritableKeyPath<ImageModel, Double>) -> Binding<Double> {
        Binding(
            get: { store.models.first { $0.id == id }?[keyPath: kp] ?? 0 },
            set: { v in if let i = store.models.firstIndex(where: { $0.id == id }) { store.models[i][keyPath: kp] = v } })
    }

    private func priceField(_ v: Binding<Double>) -> some View {
        TextField("", value: v, format: .currency(code: "USD")).multilineTextAlignment(.trailing)
    }
}

struct OutputSettings: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section("AI model") {
                Picker("Model", selection: $store.settings.modelID) {
                    ForEach(store.models) { Text($0.displayName).tag($0.id) }
                }
                Picker("Quality", selection: $store.settings.quality) {
                    ForEach(store.model.qualities) { Text($0.label).tag($0) }
                }
                if store.model.sizeMode == .custom {
                    Picker("Output size", selection: $store.settings.outputLongEdge) {
                        Text("1536 px (fast)").tag(1536)
                        Text("2048 px (MLS)").tag(2048)
                        Text("2560 px").tag(2560)
                        Text("3840 px (4K, experimental)").tag(3840)
                    }
                } else {
                    Text("This model outputs at most 1536×1024. Photos that aren't 3:2 are center-cropped to fit.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Stepper("Versions per photo: \(store.settings.variations)", value: $store.settings.variations, in: 1...4)
                if !store.model.notes.isEmpty {
                    Text(store.model.notes).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: store.settings.modelID) {
                // Keep the quality picker valid when a model offers fewer levels.
                store.settings.quality = store.effectiveQuality
            }
            Section("Processing") {
                Stepper("Photos at once: \(store.settings.concurrency)", value: $store.settings.concurrency, in: 1...6)
                Toggle("Level the horizon on this Mac before upload", isOn: $store.settings.levelHorizonLocally)
                LabeledContent("Ask before batches over") {
                    TextField("", value: $store.settings.confirmAbove, format: .currency(code: "USD")).frame(width: 90)
                }
            }
            Section("Export") {
                Picker("Exported size (long edge)", selection: $store.settings.exportLongEdge) {
                    Text("Keep model size").tag(0)
                    Text("1600 px").tag(1600)
                    Text("2048 px (most MLSs)").tag(2048)
                    Text("3000 px").tag(3000)
                    Text("4096 px").tag(4096)
                }
                Toggle("Add \"-virtually-enhanced\" to file names of altered photos", isOn: $store.settings.addDisclosureToFilename)
                Text("Exports are JPEGs with location and camera metadata removed. An edit-log.csv lists every edit for MLS disclosure.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct SpendSettings: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 24) {
                stat("This month", store.ledger.total(inMonthOf: Date()))
                stat("All time", store.ledger.total)
                stat("Average per photo", store.ledger.averagePerPhoto)
            }
            Table(Array(store.ledger.entries.reversed())) {
                TableColumn("Date") { (e: SpendEntry) in Text(e.date, style: .date) }
                TableColumn("Photo", value: \.photoName)
                TableColumn("Model", value: \.model)
                TableColumn("Estimated") { (e: SpendEntry) in Text(e.estimated.dollarString) }
                TableColumn("Actual") { (e: SpendEntry) in Text(e.actual?.dollarString ?? "n/a") }
            }
            HStack {
                Text("Actual cost comes from the token usage OpenAI returns with each edit.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear history") { store.ledger = SpendLedger() }
            }
        }
        .padding()
    }

    private func stat(_ title: String, _ v: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(v.dollarString).font(.title2.monospacedDigit())
        }
    }
}
#endif
