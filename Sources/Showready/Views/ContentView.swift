#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import ShowreadyCore

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            LibraryView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            Group {
                if let id = store.selection.first, store.selection.count == 1,
                   let current = store.photos.first(where: { $0.id == id }) {
                    CompareView(photo: Binding(
                        get: { store.photos.first { $0.id == id } ?? current },
                        set: { new in if let i = store.index(id) { store.photos[i] = new } }))
                        .id(id)
                } else if store.photos.isEmpty {
                    EmptyStateView()
                } else {
                    Text(store.selection.isEmpty ? "Select a photo" : "\(store.selection.count) photos selected")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .inspector(isPresented: $showInspector) {
                EditPanel()
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .toolbar { toolbar }
        .task { if DemoRunner.isEnabled { await DemoRunner.run(store) } }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in store.importURLs([url]) } }
                }
            }
            return true
        }
        .alert("Showready", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
            Button("OK") { store.alert = nil }
        } message: { Text(store.alert ?? "") }
        .confirmationDialog("Run this batch?",
                            isPresented: Binding(get: { store.pendingBatch != nil }, set: { if !$0 { store.pendingBatch = nil } })) {
            if let b = store.pendingBatch {
                Button("Edit \(b.ids.count) photos for about \(b.estimate.dollarString)") { store.run(b.ids) }
            }
            Button("Cancel", role: .cancel) { store.pendingBatch = nil }
        } message: {
            Text("This estimate is above your confirmation limit in Settings.")
        }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { ImportPanel.run(store) } label: { Label("Import", systemImage: "plus") }
            if store.isRunning {
                ProgressView().controlSize(.small)
                Button { store.cancel() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            Button { store.export(store.selectedIDs.isEmpty ? store.photos.map(\.id) : store.selectedIDs) } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(store.photos.allSatisfy { $0.chosenResult == nil })
            Button { showInspector.toggle() } label: { Label("Edits", systemImage: "sidebar.right") }
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54)).foregroundStyle(.secondary)
            Text("Drop listing photos or a folder here").font(.title2)
            Text("JPEG, HEIC, PNG, TIFF and camera RAW. Originals are never changed.")
                .foregroundStyle(.secondary)
            Button("Import Photos…") { ImportPanel.run(store) }.controlSize(.large)
            if store.apiKey.isEmpty {
                SettingsLink { Text("Add your OpenAI API key in Settings") }
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List(selection: $store.selection) {
            ForEach(store.photos) { p in
                HStack(spacing: 10) {
                    Image(nsImage: p.thumbnail ?? NSImage())
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 50).clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(p.options.kind.label)
                            if case .failed = p.status {
                                Text("Failed").foregroundStyle(.red)
                            } else if !p.status.label.isEmpty {
                                Text(p.status.label).foregroundStyle(p.status == .done ? Color.green : Color.orange)
                            }
                            if let c = p.lastCost { Text(c.dollarString) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(p.id)
                .contextMenu {
                    Button("Remove from list") { store.remove([p.id]) }
                    Button("Show original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([p.url]) }
                }
            }
            .onDelete { idx in store.remove(idx.map { store.photos[$0].id }) }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.photos.isEmpty {
                let total = store.estimate(ids: store.photos.map(\.id))
                HStack {
                    Text("\(store.photos.count) photos")
                    Spacer()
                    Text("All: ≈\(total.dollarString)")
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(8).background(.bar)
            }
        }
    }
}
#endif
