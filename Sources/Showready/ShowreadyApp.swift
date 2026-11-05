#if os(macOS)
import SwiftUI
import AppKit

struct ShowreadyApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var updates = UpdateController()

    init() {
        // Needed when launched with `swift run` instead of as a bundled .app.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate() }
    }

    var body: some Scene {
        WindowGroup("Rocco Show Ready") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear { updates.start() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Photos…") { ImportPanel.run(store) }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(updates)
        }
    }
}

enum ImportPanel {
    @MainActor static func run(_ store: AppStore) {
        // Hop off SwiftUI's action dispatch first. NSOpenPanel spins a nested run
        // loop even during init, which deadlocks inside a SwiftUI update
        // transaction and freezes the whole app (seen on macOS 26).
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = true
            panel.allowedContentTypes = ImageTools.supportedTypes
            panel.prompt = "Import"
            if panel.runModal() == .OK { store.importURLs(panel.urls) }
        }
    }
}
#endif
