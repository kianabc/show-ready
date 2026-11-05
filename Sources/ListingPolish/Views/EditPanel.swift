#if os(macOS)
import SwiftUI
import ListingPolishCore

/// Right-hand panel: what to change, which model, what it will cost.
struct EditPanel: View {
    @EnvironmentObject var store: AppStore

    private var primaryID: PhotoItem.ID? { store.selectedIDs.first }

    var body: some View {
        if let id = primaryID, let current = store.photos.first(where: { $0.id == id }) {
            let binding = Binding<EditOptions>(
                get: { store.photos.first { $0.id == id }?.options ?? current.options },
                set: { new in if let i = store.index(id) { store.photos[i].options = new } })
            Form {
                header(current)
                OptionsForm(o: binding)
                modelSection
                costSection(current)
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) { actions(current) }
        } else {
            Text("Select a photo to choose edits.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ p: PhotoItem) -> some View {
        Section {
            Picker("Photo type", selection: Binding(
                get: { p.options.kind },
                set: { k in
                    if let i = store.index(p.id) {
                        var o = EditOptions.defaults(for: k)
                        o.customInstructions = store.photos[i].options.customInstructions
                        store.photos[i].options = o
                    }
                })) {
                ForEach(PhotoKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if store.selection.count > 1 {
                Button("Copy these edits to all \(store.selection.count) selected \(p.options.kind.label.lowercased())s") {
                    store.applyOptionsToSelection(from: p.id)
                }
            }
        }
    }

    private var modelSection: some View {
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
                Text("This model outputs at most 1536×1024. Photos that aren't 3:2 may be re-framed.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Stepper("Versions per photo: \(store.settings.variations)", value: $store.settings.variations, in: 1...4)
            if !store.model.notes.isEmpty {
                Text(store.model.notes).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func costSection(_ p: PhotoItem) -> some View {
        let e = store.estimate(for: p)
        let selected = store.selectedIDs
        return Section("Cost") {
            LabeledContent("This photo", value: "≈ \(e.dollars.dollarString)")
            if selected.count > 1 {
                LabeledContent("\(selected.count) selected", value: "≈ \(store.estimate(ids: selected).dollarString)")
            }
            LabeledContent("Output", value: store.outputSize(for: p).description)
            Text("Estimate is \(e.basisLabel).").font(.caption).foregroundStyle(.secondary)
            if let c = p.lastCost {
                LabeledContent("Last run (actual)", value: c.dollarString)
            }
        }
    }

    private func actions(_ p: PhotoItem) -> some View {
        let ids = store.selectedIDs
        let est = store.estimate(ids: ids)
        return VStack(spacing: 8) {
            if p.options.isMaterialAlteration {
                Label("Adds or changes things buyers will see. Many MLSs require a \"virtually enhanced\" disclosure.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button {
                store.requestRun(ids)
            } label: {
                Text(ids.count > 1 ? "Edit \(ids.count) photos with AI  ≈\(est.dollarString)"
                                   : "Edit with AI  ≈\(est.dollarString)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(store.isRunning || ids.isEmpty)
            Button("Quick enhance on this Mac (free)") { store.quickEnhance(ids) }
                .frame(maxWidth: .infinity)
                .disabled(ids.isEmpty)
        }
        .padding(12)
        .background(.bar)
    }
}

struct OptionsForm: View {
    @Binding var o: EditOptions

    var body: some View {
        Section("Always") {
            Toggle("Color, exposure and white balance", isOn: $o.colorAndExposure)
            Toggle("Fix lens distortion (fisheye, barrel)", isOn: $o.lensCorrection)
            Toggle("Straighten vertical lines", isOn: $o.straightenVerticals)
                .help("Standard in professional real estate photos. Changes perspective slightly, so it is off by default.")
            Toggle("Soften harsh shadows", isOn: $o.removeHarshShadows)
        }
        if o.kind == .interior {
            Section("Interior") {
                Picker("Declutter", selection: $o.declutter) {
                    ForEach(DeclutterLevel.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Remove personal photos and items", isOn: $o.removePersonalPhotos)
                Toggle("Remove window glare", isOn: $o.removeWindowGlare)
                Toggle("Window pull (show the view outside)", isOn: $o.windowPull)
                Toggle("Remove photographer from mirrors", isOn: $o.removeReflections)
                Toggle("Turn lights on", isOn: $o.lightsOn)
                Toggle("Fire in fireplace", isOn: $o.fireInFireplace)
                Picker("TV screen", selection: $o.tvScreen) {
                    ForEach(TVScreen.allCases) { Text($0.label).tag($0) }
                }
            }
        } else {
            Section("Exterior") {
                Picker("Sky", selection: $o.sky) {
                    ForEach(SkyStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Twilight (evening, lights on)", isOn: $o.twilight)
                Toggle("Greener lawn", isOn: $o.greenLawn)
                Toggle("Remove cars, bins, hoses, debris", isOn: $o.removeCarsAndBins)
                Toggle("Remove yard signs", isOn: $o.removeSigns)
            }
        }
        Section("Extra instructions") {
            TextField("e.g. remove the ladder by the garage", text: $o.customInstructions, axis: .vertical)
                .lineLimit(2...5)
        }
    }
}
#endif
