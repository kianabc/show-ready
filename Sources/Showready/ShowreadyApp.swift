#if os(macOS)
import SwiftUI
import AppKit

struct ShowreadyApp: App {
    @StateObject private var store = AppStore()

    init() {
        // Needed when launched with `swift run` instead of as a bundled .app.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate() }
    }

    var body: some Scene {
        WindowGroup("Showready") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 700)
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
        }
    }
}

enum ImportPanel {
    @MainActor static func run(_ store: AppStore) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = ImageTools.supportedTypes
        panel.prompt = "Import"
        if panel.runModal() == .OK { store.importURLs(panel.urls) }
    }
}
#endif
